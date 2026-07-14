// FcmTokens.kt — per-user push-token registry. fcm_tokens/{uid}.tokens is an array (multi-device).
import FirebaseFirestore
import FirebaseMessaging

enum FcmTokens {
    private static var db: Firestore { Firestore.firestore() }

    static func register(_ uid: String) {
        guard !uid.isEmpty else { return }
        Messaging.messaging().token { token, _ in if let token { save(uid, token: token) } }
    }

    static func save(_ uid: String, token: String) {
        guard !uid.isEmpty, !token.isEmpty else { return }
        db.collection("fcm_tokens").document(uid)
            .setData(["tokens": FieldValue.arrayUnion([token])], merge: true)
    }

    static func unregister(_ uid: String) {
        guard !uid.isEmpty else { return }
        Messaging.messaging().token { token, _ in
            guard let token else { return }
            db.collection("fcm_tokens").document(uid)
                .setData(["tokens": FieldValue.arrayRemove([token])], merge: true)
        }
    }
}
