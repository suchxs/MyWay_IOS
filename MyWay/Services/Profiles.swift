// Profiles.kt — user @tags + profile. users/{uid} and usernames/{lower} uniqueness index.
import FirebaseFirestore

enum Profiles {
    private static var db: Firestore { Firestore.firestore() }
    private static let format = try! NSRegularExpression(pattern: "^[a-z0-9_]{3,20}$")

    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("@") { s.removeFirst() }
        return s.lowercased()
    }

    static func formatError(_ normalized: String) -> String? {
        if normalized.count < 3 { return "At least 3 characters" }
        if normalized.count > 20 { return "Keep it under 20 characters" }
        let range = NSRange(normalized.startIndex..., in: normalized)
        if format.firstMatch(in: normalized, range: range) == nil { return "Letters, numbers and _ only" }
        return nil
    }

    static func fetchTag(_ uid: String, onResult: @escaping (String?) -> Void) {
        db.collection("users").document(uid).getDocument { snap, _ in
            let tag = snap?.get("tag") as? String
            onResult(tag?.isEmpty == false ? tag : nil)
        }
    }

    static func fetchProfile(_ uid: String, onResult: @escaping (Profile?) -> Void) {
        db.collection("users").document(uid).getDocument { snap, err in
            guard let snap, err == nil else { onResult(nil); return }
            onResult(Profile(tag: snap.get("tag") as? String ?? "",
                             firstName: snap.get("firstName") as? String ?? "",
                             lastName: snap.get("lastName") as? String ?? "",
                             photo: snap.get("photo") as? String ?? ""))
        }
    }

    static func updateName(_ uid: String, first: String, last: String, onDone: @escaping (String?) -> Void) {
        db.collection("users").document(uid).setData(
            ["firstName": first.trimmingCharacters(in: .whitespaces),
             "lastName": last.trimmingCharacters(in: .whitespaces)], merge: true) { onDone($0?.localizedDescription) }
    }

    static func updatePhoto(_ uid: String, base64: String, onDone: @escaping (String?) -> Void) {
        db.collection("users").document(uid).setData(["photo": base64], merge: true) { onDone($0?.localizedDescription) }
    }

    static func updateBanner(_ uid: String, base64: String, onDone: @escaping (String?) -> Void) {
        db.collection("user_banners").document(uid).setData(["banner": base64]) { onDone($0?.localizedDescription) }
    }

    static func fetchBanner(_ uid: String, onResult: @escaping (String) -> Void) {
        db.collection("user_banners").document(uid).getDocument { snap, _ in
            onResult(snap?.get("banner") as? String ?? "")
        }
    }

    enum ClaimResult { case success(String), taken, error(String) }

    /// Atomically reserve a handle. Idempotent if it's already yours; frees the old handle on rename.
    static func claimTag(_ uid: String, display: String, onResult: @escaping (ClaimResult) -> Void) {
        let lower = normalize(display)
        let nameRef = db.collection("usernames").document(lower)
        let userRef = db.collection("users").document(uid)
        db.runTransaction({ txn, errPtr -> Any? in
            let userSnap: DocumentSnapshot
            do { userSnap = try txn.getDocument(userRef) } catch { errPtr?.pointee = error as NSError; return nil }
            let oldLower = userSnap.get("tagLower") as? String
            let owner = (try? txn.getDocument(nameRef))?.get("uid") as? String
            if let owner, owner != uid {
                errPtr?.pointee = NSError(domain: "MyWay", code: 409); return nil   // taken
            }
            txn.setData(["uid": uid], forDocument: nameRef)
            if let oldLower, oldLower != lower {
                txn.deleteDocument(self.db.collection("usernames").document(oldLower))
            }
            var data: [String: Any] = ["tag": display, "tagLower": lower]
            if !userSnap.exists { data["createdAt"] = FieldValue.serverTimestamp() }
            txn.setData(data, forDocument: userRef, merge: true)
            return nil
        }) { _, error in
            if let error = error as NSError? {
                onResult(error.code == 409 ? .taken : .error(error.localizedDescription))
            } else {
                onResult(.success(display))
            }
        }
    }

    static func deleteMyData(_ uid: String, tagLower: String, onDone: @escaping (String?) -> Void) {
        let batch = db.batch()
        batch.deleteDocument(db.collection("users").document(uid))
        if !tagLower.isEmpty { batch.deleteDocument(db.collection("usernames").document(tagLower)) }
        batch.deleteDocument(db.collection("user_banners").document(uid))
        batch.commit { onDone($0?.localizedDescription) }
    }
}
