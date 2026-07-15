// Friends.kt — find users by @tag, requests, friendships.
//   friendRequests/{from_to}, friendships/{sortedPair}
import FirebaseFirestore

enum Friends {
    private static var db: Firestore { Firestore.firestore() }
    private static func pairId(_ a: String, _ b: String) -> String { [a, b].sorted().joined(separator: "_") }

    /// Prefix search on tagLower, excluding yourself.
    static func search(_ rawQuery: String, myUid: String, onResult: @escaping ([UserHit]) -> Void) {
        let q = Profiles.normalize(rawQuery)
        guard !q.isEmpty else { onResult([]); return }
        db.collection("users").order(by: "tagLower").start(at: [q]).end(at: [q + "\u{f8ff}"]).limit(to: 25)
            .getDocuments { snap, _ in
                guard let snap else { onResult([]); return }
                onResult(snap.documents.compactMap { d in
                    guard let tag = d.get("tag") as? String, d.documentID != myUid else { return nil }
                    return UserHit(uid: d.documentID, tag: tag,
                                   firstName: d.get("firstName") as? String ?? "",
                                   lastName: d.get("lastName") as? String ?? "",
                                   photo: d.get("photo") as? String ?? "")
                })
            }
    }

    static func sendRequest(myUid: String, myTag: String, target: UserHit, onDone: @escaping (String?) -> Void) {
        db.collection("friendRequests").document("\(myUid)_\(target.uid)").setData([
            "from": myUid, "fromTag": myTag, "to": target.uid, "toTag": target.tag,
            "createdAt": FieldValue.serverTimestamp(),
        ]) { onDone($0?.localizedDescription) }
    }

    static func listenIncoming(_ myUid: String, onChange: @escaping ([FriendRequest]) -> Void) -> ListenerRegistration {
        db.collection("friendRequests").whereField("to", isEqualTo: myUid)
            .addSnapshotListener { snap, _ in if let snap { onChange(mapRequests(snap)) } }
    }

    static func listenOutgoing(_ myUid: String, onChange: @escaping ([FriendRequest]) -> Void) -> ListenerRegistration {
        db.collection("friendRequests").whereField("from", isEqualTo: myUid)
            .addSnapshotListener { snap, _ in if let snap { onChange(mapRequests(snap)) } }
    }

    private static func mapRequests(_ snap: QuerySnapshot) -> [FriendRequest] {
        snap.documents.compactMap { d in
            guard let from = d.get("from") as? String, let to = d.get("to") as? String else { return nil }
            return FriendRequest(id: d.documentID, fromUid: from, fromTag: d.get("fromTag") as? String ?? "",
                                 toUid: to, toTag: d.get("toTag") as? String ?? "")
        }
    }

    static func accept(_ req: FriendRequest, onDone: @escaping (String?) -> Void) {
        db.collection("friendships").document(pairId(req.fromUid, req.toUid)).setData([
            "users": [req.fromUid, req.toUid],
            "tagByUid": [req.fromUid: req.fromTag, req.toUid: req.toTag],
            "closeByUid": [req.fromUid: false, req.toUid: false],
        ]) { err in
            if let err { onDone(err.localizedDescription); return }
            db.collection("friendRequests").document(req.id).delete { _ in onDone(nil) }
        }
    }

    static func deleteRequest(_ req: FriendRequest, onDone: @escaping (String?) -> Void) {
        db.collection("friendRequests").document(req.id).delete { onDone($0?.localizedDescription) }
    }

    static func listenFriends(_ myUid: String, onChange: @escaping ([UserHit]) -> Void) -> ListenerRegistration {
        db.collection("friendships").whereField("users", arrayContains: myUid)
            .addSnapshotListener { snap, _ in
                guard let snap else { return }
                onChange(snap.documents.compactMap { d in
                    guard let users = d.get("users") as? [String],
                          let other = users.first(where: { $0 != myUid }) else { return nil }
                    let tags = d.get("tagByUid") as? [String: String]
                    let close = d.get("closeByUid") as? [String: Bool]
                    return UserHit(uid: other, tag: tags?[other] ?? "friend", isClose: close?[myUid] ?? false)
                })
            }
    }

    static func removeFriend(myUid: String, otherUid: String, onDone: @escaping (String?) -> Void) {
        db.collection("friendships").document(pairId(myUid, otherUid)).delete { onDone($0?.localizedDescription) }
    }

    static func setCloseFriend(myUid: String, otherUid: String, isClose: Bool, onDone: @escaping (String?) -> Void) {
        db.collection("friendships").document(pairId(myUid, otherUid))
            .setData(["closeByUid": [myUid: isClose]], merge: true) { onDone($0?.localizedDescription) }
    }

    static func fetchFriendUids(_ myUid: String, onResult: @escaping ([String]) -> Void) {
        db.collection("friendships").whereField("users", arrayContains: myUid).getDocuments { snap, _ in
            onResult(snap?.documents.compactMap { ($0.get("users") as? [String])?.first { $0 != myUid } } ?? [])
        }
    }

    static func fetchCloseFriendUids(_ myUid: String, onResult: @escaping ([String]) -> Void) {
        db.collection("friendships").whereField("users", arrayContains: myUid).getDocuments { snap, _ in
            onResult(snap?.documents.compactMap { d in
                guard let users = d.get("users") as? [String], let other = users.first(where: { $0 != myUid }) else { return nil }
                return (d.get("closeByUid") as? [String: Bool])?[myUid] == true ? other : nil
            } ?? [])
        }
    }
}
