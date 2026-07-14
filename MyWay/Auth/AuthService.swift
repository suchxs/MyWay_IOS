// Firebase auth wrapper for the three providers the Android app supports: email/password, Google, GitHub.
// iOS uses GoogleSignIn-iOS (Android used Play Services) and Firebase's hosted OAuth for GitHub.
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import UIKit

enum AuthService {
    static var currentUid: String? { Auth.auth().currentUser?.uid }
    static var emailVerified: Bool { Auth.auth().currentUser?.isEmailVerified ?? false }

    static func signIn(email: String, password: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { result, err in
            if let err { completion(.failure(err)); return }
            completion(.success(result?.user.isEmailVerified ?? false))   // false ⇒ prompt verify
        }
    }

    static func register(email: String, password: String, completion: @escaping (Error?) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { result, err in
            if let err { completion(err); return }
            result?.user.sendEmailVerification { _ in completion(nil) }
        }
    }

    static func sendPasswordReset(_ email: String, completion: @escaping () -> Void) {
        Auth.auth().sendPasswordReset(withEmail: email) { _ in completion() }   // same reply whether or not it exists
    }

    static func resendVerification() { Auth.auth().currentUser?.sendEmailVerification() }

    static func signOut() {
        if let uid = currentUid { FcmTokens.unregister(uid) }
        try? Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
    }

    // ── Google ────────────────────────────────────────────────────────────────────
    static func signInWithGoogle(completion: @escaping (Error?) -> Void) {
        guard let clientID = FirebaseApp.app()?.options.clientID,
              let root = UIApplication.topViewController() else {
            completion(NSError(domain: "MyWay", code: 0)); return
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.signIn(withPresenting: root) { result, err in
            if let err { completion(err); return }
            guard let idToken = result?.user.idToken?.tokenString,
                  let accessToken = result?.user.accessToken.tokenString else {
                completion(NSError(domain: "MyWay", code: 1)); return
            }
            let cred = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            Auth.auth().signIn(with: cred) { _, e in completion(e) }
        }
    }

    // ── GitHub (Firebase-hosted OAuth) ─────────────────────────────────────────────
    static func signInWithGitHub(completion: @escaping (Error?) -> Void) {
        let provider = OAuthProvider(providerID: "github.com")
        provider.getCredentialWith(nil) { cred, err in
            if let err { completion(err); return }
            guard let cred else { completion(NSError(domain: "MyWay", code: 2)); return }
            Auth.auth().signIn(with: cred) { _, e in completion(e) }
        }
    }
}

extension UIApplication {
    static func topViewController() -> UIViewController? {
        let scene = shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
