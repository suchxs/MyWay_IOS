// 1:1 call signalling. One doc per pair keyed by pairId (which is also the LiveKit room name):
//   calls/{pairId} { from, fromTag, fromPhoto, to, toTag, status: ringing|active, startedAt }
// The doc only rings/accepts/ends the call; the audio itself flows through LiveKit (token minted by
// the `livekitToken` Cloud Function). Deleting the doc = hang up / decline, which both sides listen for.
import FirebaseFirestore
import FirebaseFunctions

struct Call: Identifiable, Equatable {
    let id: String        // = pairId, also the LiveKit room name
    let from, fromTag, fromPhoto: String
    let to, toTag: String
    var status: String    // "ringing" → "active"
    var video = false     // caller requested a video call → callee enables camera on accept
    var room: String { id }
}

enum Calls {
    private static var db: Firestore { Firestore.firestore() }
    private static func ref(_ id: String) -> DocumentReference { db.collection("calls").document(id) }

    static func start(_ c: Call) {
        ref(c.id).setData(["from": c.from, "fromTag": c.fromTag, "fromPhoto": c.fromPhoto,
                           "to": c.to, "toTag": c.toTag, "status": "ringing", "video": c.video,
                           "startedAt": FieldValue.serverTimestamp()])
    }

    static func accept(_ id: String) { ref(id).updateData(["status": "active"]) }
    static func end(_ id: String) { ref(id).delete() }

    /// Ringing calls addressed to me (single-field `to` query — no composite index needed).
    static func listenIncoming(_ myUid: String, onChange: @escaping (Call?) -> Void) -> ListenerRegistration {
        db.collection("calls").whereField("to", isEqualTo: myUid).addSnapshotListener { snap, err in
            if err != nil { return }   // transient/permission error — don't spuriously clear an incoming call
            onChange(snap?.documents.compactMap(parse).first { $0.status == "ringing" })
        }
    }

    /// Watch one call doc for accept (→ active) or hang-up (→ deleted, parsed as nil).
    static func listen(_ id: String, onChange: @escaping (Call?) -> Void) -> ListenerRegistration {
        ref(id).addSnapshotListener { d, err in
            if err != nil { return }   // don't treat a listener error as "peer hung up" (was ending calls instantly)
            onChange(d.flatMap(parse))
        }
    }

    private static func parse(_ d: DocumentSnapshot) -> Call? {
        guard d.exists, let from = d.get("from") as? String, let to = d.get("to") as? String else { return nil }
        return Call(id: d.documentID, from: from, fromTag: d.get("fromTag") as? String ?? "",
                    fromPhoto: d.get("fromPhoto") as? String ?? "", to: to, toTag: d.get("toTag") as? String ?? "",
                    status: d.get("status") as? String ?? "ringing", video: d.get("video") as? Bool ?? false)
    }

    // ── Group calls ──────────────────────────────────────────────────────────────
    // A group call is just a shared room (name = gid) that anyone can join — no ringing/callee.
    // group_calls/{gid}.participants tracks who's currently in, so members see "call in progress".
    private static func groupRef(_ gid: String) -> DocumentReference { db.collection("group_calls").document(gid) }

    // Join in a transaction so we can tell the FIRST joiner (→ "started a call") from the rest (→ "joined").
    static func joinGroupCall(_ gid: String, groupName: String, uid: String, onJoined: @escaping (_ wasFirst: Bool) -> Void = { _ in }) {
        let ref = groupRef(gid)
        db.runTransaction({ txn, _ in
            let snap = try? txn.getDocument(ref)
            let existing = (snap?.get("participants") as? [String]) ?? []
            let wasFirst = existing.isEmpty
            var data: [String: Any] = ["gid": gid, "groupName": groupName,
                                       "participants": existing.contains(uid) ? existing : existing + [uid]]
            if wasFirst { data["startedAt"] = FieldValue.serverTimestamp() }
            txn.setData(data, forDocument: ref, merge: true)
            return wasFirst
        }) { result, _ in onJoined((result as? Bool) ?? false) }
    }

    // Leave in a transaction. If I'm the LAST one out, delete the doc and report the total call duration
    // (→ "call ended, lasted X"); otherwise just report a normal "left the call".
    // ponytail: a force-quit leaves a stale uid; a LiveKit room_empty webhook would clear it
    // authoritatively. Fine for a foreground demo.
    static func leaveGroupCall(_ gid: String, uid: String, onLeft: @escaping (_ wasLast: Bool, _ seconds: Int) -> Void = { _, _ in }) {
        let ref = groupRef(gid)
        db.runTransaction({ txn, _ -> Any? in
            guard let snap = try? txn.getDocument(ref), snap.exists else { return ["last": false, "sec": 0] }
            let remaining = ((snap.get("participants") as? [String]) ?? []).filter { $0 != uid }
            if remaining.isEmpty {
                let started = (snap.get("startedAt") as? Timestamp)?.dateValue()
                let sec = started.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
                txn.deleteDocument(ref)
                return ["last": true, "sec": sec]
            }
            txn.updateData(["participants": remaining], forDocument: ref)
            return ["last": false, "sec": 0]
        }) { result, _ in
            let d = result as? [String: Any]
            onLeft((d?["last"] as? Bool) ?? false, (d?["sec"] as? Int) ?? 0)
        }
    }

    /// Current participants of a group call (empty = no call in progress).
    static func listenGroupCall(_ gid: String, onChange: @escaping ([String]) -> Void) -> ListenerRegistration {
        groupRef(gid).addSnapshotListener { d, err in
            if err != nil { return }   // ignore transient/permission errors — keep the banner state
            onChange(d?.get("participants") as? [String] ?? [])
        }
    }

    /// Mint a LiveKit access token for [room] via the Cloud Function. Returns (token, wss-url).
    static func token(room: String, onDone: @escaping (String?, String?) -> Void) {
        Functions.functions().httpsCallable("livekitToken").call(["room": room]) { result, error in
            if let error { print("livekitToken error:", error.localizedDescription); onDone(nil, nil); return }
            let data = result?.data as? [String: Any]
            onDone(data?["token"] as? String, data?["url"] as? String)
        }
    }
}
