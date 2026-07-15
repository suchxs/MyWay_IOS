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
                     reads: d.get("reads") as? [String: Int64] ?? [:])
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
                                 ts: d.get("ts") as? Int64 ?? 0)
                })
            }
    }

    static func markRead(_ gid: String, uid: String, ts: Int64) {
        db.collection("groups").document(gid).updateData(["reads.\(uid)": ts])
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
        f["ts"] = Int64(Date().timeIntervalSince1970 * 1000)   // client millis, matches Android ordering
        db.collection("groups").document(gid).collection("messages").document().setData(f)
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
}
