// PrivateMessages.kt → Swift. 1-on-1 chats. chatId = sorted uids joined by "_".
//   private_chats/{chatId} { users[], tags{}, lastMsg, lastTs }
//   private_chats/{chatId}/messages/{mid} { from, fromTag, text, image, ts }
import FirebaseFirestore

struct PrivateChat: Identifiable, Equatable {
    let id: String
    let users: [String]
    let tags: [String: String]
    var lastMsg = ""
    var lastTs: Int64 = 0
    var reads: [String: Int64] = [:]
    func otherUid(_ myUid: String) -> String { users.first { $0 != myUid } ?? "" }
    func otherTag(_ myUid: String) -> String { tags[otherUid(myUid)] ?? "User" }
}

enum PrivateMessages {
    private static var db: Firestore { Firestore.firestore() }
    static func pairId(_ a: String, _ b: String) -> String { [a, b].sorted().joined(separator: "_") }

    static func listenMyChats(_ myUid: String, onChange: @escaping ([PrivateChat]) -> Void) -> ListenerRegistration {
        // No orderBy — arrayContains + orderBy on another field needs a composite index. Sort in memory.
        db.collection("private_chats").whereField("users", arrayContains: myUid)
            .addSnapshotListener { snap, _ in
                guard let snap else { return }
                let chats = snap.documents.compactMap { d -> PrivateChat? in
                    guard let users = d.get("users") as? [String] else { return nil }
                    return PrivateChat(id: d.documentID, users: users, tags: d.get("tags") as? [String: String] ?? [:],
                                       lastMsg: d.get("lastMsg") as? String ?? "", lastTs: d.get("lastTs") as? Int64 ?? 0,
                                       reads: d.get("reads") as? [String: Int64] ?? [:])
                }
                onChange(chats.sorted { $0.lastTs > $1.lastTs })
            }
    }

    static func listenChat(_ chatId: String, onChange: @escaping (PrivateChat?) -> Void) -> ListenerRegistration {
        db.collection("private_chats").document(chatId).addSnapshotListener { d, _ in
            guard let d, d.exists, let users = d.get("users") as? [String] else { onChange(nil); return }
            onChange(PrivateChat(id: chatId, users: users, tags: d.get("tags") as? [String: String] ?? [:],
                                 lastMsg: d.get("lastMsg") as? String ?? "", lastTs: d.get("lastTs") as? Int64 ?? 0,
                                 reads: d.get("reads") as? [String: Int64] ?? [:]))
        }
    }

    static func markRead(_ chatId: String, uid: String, ts: Int64) {
        db.collection("private_chats").document(chatId).updateData(["reads.\(uid)": ts])
    }

    static func listenMessages(_ chatId: String, onChange: @escaping ([GroupMessage]) -> Void) -> ListenerRegistration {
        db.collection("private_chats").document(chatId).collection("messages").order(by: "ts")
            .addSnapshotListener { snap, _ in
                guard let snap else { return }
                onChange(snap.documents.map { d in
                    GroupMessage(id: d.documentID, from: d.get("from") as? String ?? "", fromTag: d.get("fromTag") as? String ?? "",
                                 text: d.get("text") as? String ?? "", image: d.get("image") as? String ?? "",
                                 pinLat: d.get("pinLat") as? Double, pinLng: d.get("pinLng") as? Double,
                                 pinName: d.get("pinName") as? String ?? "", pinNote: d.get("pinNote") as? String ?? "",
                                 pinPlaceId: d.get("pinPlaceId") as? String ?? "", system: d.get("system") as? Bool ?? false,
                                 liveFrom: d.get("liveFrom") as? String ?? "", edited: d.get("edited") as? Bool ?? false,
                                 unsent: d.get("unsent") as? Bool ?? false, ts: d.get("ts") as? Int64 ?? 0)
                })
            }
    }

    /// Edit a text message (author only). `newPreview` non-nil ⇒ this was the newest message, so also
    /// refresh the inbox preview on the parent chat doc.
    static func editMessage(_ chatId: String, mid: String, text: String, newPreview: String?) {
        let body = text.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return }
        let ref = db.collection("private_chats").document(chatId)
        ref.collection("messages").document(mid).updateData(["text": body, "edited": true])
        if newPreview != nil { ref.updateData(["lastMsg": body]) }
    }

    /// Unsend a message (author only). Soft-delete: keeps the message as a tombstone with content cleared.
    /// Updates the inbox preview when it was the newest message.
    static func unsendMessage(_ chatId: String, mid: String, isLast: Bool) {
        let ref = db.collection("private_chats").document(chatId)
        ref.collection("messages").document(mid).updateData([
            "unsent": true, "text": "", "image": "", "liveFrom": "", "edited": false,
            "pinLat": FieldValue.delete(), "pinLng": FieldValue.delete(), "pinName": "", "pinNote": "", "pinPlaceId": "",
        ])
        if isLast { ref.updateData(["lastMsg": "Unsent a message"]) }
    }

    static func sendMessage(_ chatId: String, fromUid: String, fromTag: String, otherUid: String, otherTag: String, text: String) {
        let body = text.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return }
        post(chatId, fromUid: fromUid, fromTag: fromTag, otherUid: otherUid, otherTag: otherTag,
             preview: body, msg: ["from": fromUid, "fromTag": fromTag, "text": body])
    }

    static func sendImage(_ chatId: String, fromUid: String, fromTag: String, otherUid: String, otherTag: String, base64: String) {
        guard !base64.isEmpty else { return }
        post(chatId, fromUid: fromUid, fromTag: fromTag, otherUid: otherUid, otherTag: otherTag,
             preview: "📷 Image", msg: ["from": fromUid, "fromTag": fromTag, "text": "", "image": base64])
    }

    /// Announce a live-location share in the DM; the card reads live_shares/{fromUid} when tapped.
    static func postLiveShare(_ chatId: String, fromUid: String, fromTag: String, otherUid: String, otherTag: String) {
        post(chatId, fromUid: fromUid, fromTag: fromTag, otherUid: otherUid, otherTag: otherTag,
             preview: "🔴 Live location", msg: ["from": fromUid, "fromTag": fromTag, "text": "", "liveFrom": fromUid])
    }

    private static func post(_ chatId: String, fromUid: String, fromTag: String, otherUid: String, otherTag: String,
                             preview: String, msg: [String: Any]) {
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        var m = msg; m["ts"] = ts
        let batch = db.batch()
        let chatRef = db.collection("private_chats").document(chatId)
        batch.setData(["users": [fromUid, otherUid].sorted(), "tags": [fromUid: fromTag, otherUid: otherTag],
                       "lastMsg": preview, "lastTs": ts], forDocument: chatRef, merge: true)
        batch.setData(m, forDocument: chatRef.collection("messages").document())
        batch.commit()
    }
}
