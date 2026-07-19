// Groups.kt — group circles + chat.
//   groups/{gid} { name, owner, members[], admins[], tags{}, photo, tripActive, reads{} }
//   groups/{gid}/messages/{mid} { from, fromTag, text, image, pin*, system, liveFrom, ts }
import FirebaseFirestore

enum Groups {
    private static var db: Firestore { Firestore.firestore() }

    static func createGroup(owner: String, ownerTag: String, name: String, friends: [UserHit], onDone: @escaping (String?) -> Void) {
        let members = ([owner] + friends.map { $0.uid })
        let uniqueMembers = Array(NSOrderedSet(array: members)) as! [String]
        var tags = [owner: ownerTag]
        friends.forEach { tags[$0.uid] = $0.tag }
        db.collection("groups").document().setData([
            "name": name.trimmingCharacters(in: .whitespaces),
            "owner": owner, "members": uniqueMembers, "admins": [owner], "tags": tags,
            "createdAt": FieldValue.serverTimestamp(),
        ]) { onDone($0?.localizedDescription) }
    }

    static func listenMyGroups(_ uid: String, onChange: @escaping ([TravelGroup]) -> Void) -> ListenerRegistration {
        db.collection("groups").whereField("members", arrayContains: uid)
            .addSnapshotListener { snap, _ in
                if let snap { onChange(snap.documents.compactMap { mapGroup($0.documentID, $0) }) }
            }
    }

    static func fetchMyGroups(_ uid: String, onResult: @escaping ([TravelGroup]) -> Void) {
        db.collection("groups").whereField("members", arrayContains: uid).getDocuments { snap, _ in
            onResult(snap?.documents.compactMap { mapGroup($0.documentID, $0) } ?? [])
        }
    }

    static func fetchNamePhoto(_ gid: String, onResult: @escaping (String, String) -> Void) {
        db.collection("groups").document(gid).getDocument { d, _ in
            onResult(d?.get("name") as? String ?? "Group", d?.get("photo") as? String ?? "")
        }
    }

    static func listenGroup(_ gid: String, onChange: @escaping (TravelGroup?) -> Void) -> ListenerRegistration {
        db.collection("groups").document(gid).addSnapshotListener { doc, _ in
            onChange(doc?.exists == true ? mapGroup(gid, doc!) : nil)
        }
    }

    private static func mapGroup(_ id: String, _ d: DocumentSnapshot) -> TravelGroup? {
        guard let owner = d.get("owner") as? String else { return nil }
        return TravelGroup(id: id, name: d.get("name") as? String ?? "Group", owner: owner,
                     members: d.get("members") as? [String] ?? [],
                     admins: d.get("admins") as? [String] ?? [],
                     tags: d.get("tags") as? [String: String] ?? [:],
                     photo: d.get("photo") as? String ?? "",
                     tripActive: d.get("tripActive") as? Bool ?? false,
                     reads: d.get("reads") as? [String: Int64] ?? [:],
                     lastMsg: d.get("lastMsg") as? String ?? "",
                     lastTs: d.get("lastTs") as? Int64 ?? 0,
                     tripScheduledAt: (d.get("tripScheduledAt") as? Timestamp)?.dateValue(),
                     tripGoing: d.get("tripGoing") as? [String] ?? [])
    }

    static func updatePhoto(_ gid: String, base64: String, onDone: @escaping (String?) -> Void) {
        db.collection("groups").document(gid).updateData(["photo": base64]) { onDone($0?.localizedDescription) }
    }

    // ── Chat ─────────────────────────────────────────────────────────────────────
    static func listenMessages(_ gid: String, onChange: @escaping ([GroupMessage]) -> Void) -> ListenerRegistration {
        db.collection("groups").document(gid).collection("messages").order(by: "ts")
            .addSnapshotListener { snap, _ in
                guard let snap else { return }
                onChange(snap.documents.map { d in
                    GroupMessage(id: d.documentID, from: d.get("from") as? String ?? "",
                                 fromTag: d.get("fromTag") as? String ?? "",
                                 text: d.get("text") as? String ?? "", image: d.get("image") as? String ?? "",
                                 pinLat: d.get("pinLat") as? Double, pinLng: d.get("pinLng") as? Double,
                                 pinName: d.get("pinName") as? String ?? "", pinNote: d.get("pinNote") as? String ?? "",
                                 pinPlaceId: d.get("pinPlaceId") as? String ?? "",
                                 system: d.get("system") as? Bool ?? false,
                                 liveFrom: d.get("liveFrom") as? String ?? "",
                                 edited: d.get("edited") as? Bool ?? false,
                                 unsent: d.get("unsent") as? Bool ?? false,
                                 collName: d.get("collName") as? String ?? "", collIcon: d.get("collIcon") as? String ?? "",
                                 collPins: parseSharedPins(d.get("collPins")),
                                 ts: d.get("ts") as? Int64 ?? 0)
                })
            }
    }

    static func markRead(_ gid: String, uid: String, ts: Int64) {
        db.collection("groups").document(gid).updateData(["reads.\(uid)": ts])
    }

    /// Edit a text message (author only, enforced by rules). Flags it edited; refreshes the inbox
    /// preview when it was the newest message.
    static func editMessage(_ gid: String, mid: String, text: String, newPreview: String?) {
        let body = text.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return }
        let gref = db.collection("groups").document(gid)
        gref.collection("messages").document(mid).updateData(["text": body, "edited": true])
        if newPreview != nil { gref.updateData(["lastMsg": body]) }
    }

    /// Unsend a message (author only). Soft-delete: the message stays as a tombstone ("… unsent a
    /// message") with its content cleared. Updates the inbox preview when it was the newest message.
    static func unsendMessage(_ gid: String, mid: String, isLast: Bool) {
        let gref = db.collection("groups").document(gid)
        gref.collection("messages").document(mid).updateData([
            "unsent": true, "text": "", "image": "", "liveFrom": "", "edited": false,
            "pinLat": FieldValue.delete(), "pinLng": FieldValue.delete(), "pinName": "", "pinNote": "", "pinPlaceId": "",
            "collName": "", "collIcon": "", "collPins": FieldValue.delete(),
        ])
        if isLast { gref.updateData(["lastMsg": "Unsent a message"]) }
    }

    static func sendMessage(_ gid: String, fromUid: String, fromTag: String, text: String) {
        let body = text.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return }
        post(gid, ["from": fromUid, "fromTag": fromTag, "text": body])
    }

    static func sendImage(_ gid: String, fromUid: String, fromTag: String, base64: String) {
        guard !base64.isEmpty else { return }
        post(gid, ["from": fromUid, "fromTag": fromTag, "text": "", "image": base64])
    }

    static func sharePin(_ gid: String, fromUid: String, fromTag: String, lat: Double, lng: Double, name: String, note: String, placeId: String) {
        post(gid, ["from": fromUid, "fromTag": fromTag, "text": "",
                   "pinLat": lat, "pinLng": lng, "pinName": name, "pinNote": note, "pinPlaceId": placeId])
    }

    static func shareCollection(_ gid: String, fromUid: String, fromTag: String, name: String, icon: String, pins: [SharedPin]) {
        guard !pins.isEmpty else { return }
        post(gid, ["from": fromUid, "fromTag": fromTag, "text": "",
                   "collName": name, "collIcon": icon, "collPins": pins.map(\.dict)])
    }

    static func postSystem(_ gid: String, text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        post(gid, ["from": "system", "fromTag": "", "text": text, "system": true])
    }

    /// Announce a live-location share in a group chat; the card reads live_shares/{fromUid} when tapped.
    static func postLiveShare(_ gid: String, fromUid: String, fromTag: String) {
        post(gid, ["from": fromUid, "fromTag": fromTag, "text": "", "liveFrom": fromUid])
    }

    private static func post(_ gid: String, _ fields: [String: Any]) {
        var f = fields
        let ts = Int64(Date().timeIntervalSince1970 * 1000)   // client millis, matches Android ordering
        f["ts"] = ts
        let gref = db.collection("groups").document(gid)
        let batch = db.batch()
        batch.setData(f, forDocument: gref.collection("messages").document())
        // Mirror DMs: keep an inbox preview on the group doc so the unified Messages list can sort/show it.
        batch.setData(["lastMsg": previewOf(f), "lastTs": ts], forDocument: gref, merge: true)
        batch.commit()
    }

    /// Inbox preview for a message (media get an emoji label; text is shown verbatim).
    static func previewOf(_ f: [String: Any]) -> String {
        if let img = f["image"] as? String, !img.isEmpty { return "📷 Photo" }
        if let live = f["liveFrom"] as? String, !live.isEmpty { return "🔴 Live location" }
        if let coll = f["collName"] as? String, !((f["collPins"] as? [Any])?.isEmpty ?? true) { return "🗂️ " + (coll.isEmpty ? "Collection" : coll) }
        if f["pinLat"] != nil { return "📍 " + ((f["pinName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Location") }
        return f["text"] as? String ?? ""
    }
    static func previewOf(_ m: GroupMessage) -> String {
        if !m.image.isEmpty { return "📷 Photo" }
        if !m.liveFrom.isEmpty { return "🔴 Live location" }
        if !m.collPins.isEmpty { return "🗂️ " + (m.collName.isEmpty ? "Collection" : m.collName) }
        if m.pinLat != nil { return "📍 " + (m.pinName.isEmpty ? "Location" : m.pinName) }
        return m.text
    }

    // ── Membership / roles ────────────────────────────────────────────────────────
    static func addMember(_ gid: String, friend: UserHit, onDone: @escaping (String?) -> Void) {
        db.collection("groups").document(gid).updateData([
            "members": FieldValue.arrayUnion([friend.uid]),
            "tags.\(friend.uid)": friend.tag,
        ]) { onDone($0?.localizedDescription) }
    }

    static func kickMember(_ gid: String, uid: String, onDone: @escaping (String?) -> Void) {
        db.collection("groups").document(gid).updateData([
            "members": FieldValue.arrayRemove([uid]),
            "admins": FieldValue.arrayRemove([uid]),
            "tags.\(uid)": FieldValue.delete(),
        ]) { onDone($0?.localizedDescription) }
    }

    static func setAdmin(_ gid: String, uid: String, makeAdmin: Bool, onDone: @escaping (String?) -> Void) {
        let op = makeAdmin ? FieldValue.arrayUnion([uid]) : FieldValue.arrayRemove([uid])
        db.collection("groups").document(gid).updateData(["admins": op]) { onDone($0?.localizedDescription) }
    }

    static func leaveGroup(_ gid: String, uid: String, onDone: @escaping (String?) -> Void) {
        kickMember(gid, uid: uid, onDone: onDone)
    }

    /// Delete a group. Ends any live trip first so participant docs are removed — otherwise every
    /// member's map keeps their avatar markers (Firestore doesn't cascade-delete subcollections/queries).
    static func deleteGroup(_ gid: String, onDone: @escaping () -> Void = {}) {
        Trip.endSession(gid) { _ in
            db.collection("groups").document(gid).delete { _ in onDone() }
        }
    }
}
