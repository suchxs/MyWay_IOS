// LiveShare.kt → Swift. Messenger-style live-location sharing. One doc per user keyed by uid.
//   live_shares/{uid} { uid, tag, photo, groups[], allFriends, closeFriends, uids[], visibleTo[], lat, lng, updatedAt, expireAt }
import FirebaseFirestore

enum LiveShare {
    static let DURATION: TimeInterval = 60 * 60   // 1 hour

    struct State: Equatable {
        let uid, tag, photo: String
        var groups: [String] = []
        var allFriends = false
        var closeFriends = false
        var uids: [String] = []
        var visibleTo: [String] = []
        let lat, lng: Double?
        let expiresAt: TimeInterval
        var active: Bool { expiresAt > Date().timeIntervalSince1970 * 1000 }
    }

    private static var db: Firestore { Firestore.firestore() }
    private static func ref(_ uid: String) -> DocumentReference { db.collection("live_shares").document(uid) }
    private static func expiry() -> Timestamp { Timestamp(date: Date().addingTimeInterval(DURATION)) }

    static func start(uid: String, tag: String, photo: String, groups: [String] = [], allFriends: Bool = false,
                      closeFriends: Bool = false, uids: [String] = [], visibleTo: [String] = [],
                      lat: Double, lng: Double, onDone: @escaping (String?) -> Void) {
        var data: [String: Any] = ["uid": uid, "tag": tag, "photo": photo, "groups": groups,
                                   "allFriends": allFriends, "closeFriends": closeFriends, "uids": uids, "visibleTo": visibleTo,
                                   "updatedAt": FieldValue.serverTimestamp(), "expireAt": expiry()]
        if lat != 0 || lng != 0 { data["lat"] = lat; data["lng"] = lng }
        ref(uid).setData(data) { onDone($0?.localizedDescription) }
    }

    static func updateLocation(_ uid: String, lat: Double, lng: Double) {
        ref(uid).updateData(["lat": lat, "lng": lng, "updatedAt": FieldValue.serverTimestamp()])
    }

    static func stop(_ uid: String, onDone: @escaping (String?) -> Void = { _ in }) {
        ref(uid).delete { onDone($0?.localizedDescription) }
    }

    static func listen(_ uid: String, onChange: @escaping (State?) -> Void) -> ListenerRegistration {
        ref(uid).addSnapshotListener { d, _ in onChange(parse(d)) }
    }

    static func listenVisible(_ myUid: String, onChange: @escaping ([State]) -> Void) -> ListenerRegistration {
        db.collection("live_shares").whereField("visibleTo", arrayContains: myUid)
            .addSnapshotListener { snap, _ in
                guard let snap else { return }
                onChange(snap.documents.compactMap { parse($0) }.filter { $0.active })
            }
    }

    private static func parse(_ d: DocumentSnapshot?) -> State? {
        guard let d, d.exists, let uid = d.get("uid") as? String else { return nil }
        return State(uid: uid, tag: d.get("tag") as? String ?? "", photo: d.get("photo") as? String ?? "",
                     groups: d.get("groups") as? [String] ?? [], allFriends: d.get("allFriends") as? Bool ?? false,
                     closeFriends: d.get("closeFriends") as? Bool ?? false, uids: d.get("uids") as? [String] ?? [],
                     visibleTo: d.get("visibleTo") as? [String] ?? [],
                     lat: d.get("lat") as? Double, lng: d.get("lng") as? Double,
                     expiresAt: (d.get("expireAt") as? Timestamp).map { $0.dateValue().timeIntervalSince1970 * 1000 } ?? 0)
    }
}
