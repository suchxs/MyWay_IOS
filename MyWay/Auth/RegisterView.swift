// RegisterActivity.kt → SwiftUI. Email/password sign-up; sends the verification email, then bounces
// back to Login (Firebase's auth listener keeps the user signed out until verified).
import SwiftUI

struct RegisterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var loading = false
    @State private var sent = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Create account").font(.system(size: 32, weight: .bold)).foregroundColor(Brand.tealDeep).padding(.top, 32)
            Text("Join MyWay and travel together").foregroundColor(.secondary).padding(.bottom, 16)

            AuthTextField(title: "Email", text: $email, keyboard: .emailAddress, enabled: !loading)
            AuthTextField(title: "Password", text: $password, isSecure: true, enabled: !loading)
            AuthTextField(title: "Confirm password", text: $confirm, isSecure: true, enabled: !loading)

            if let error { Text(error).foregroundColor(.red).font(.subheadline) }

            Button(action: register) {
                if loading { ProgressView().tint(.white) } else { Text("Register").fontWeight(.bold).foregroundColor(.white) }
            }
            .frame(maxWidth: .infinity, minHeight: 56).background(Brand.teal)
            .clipShape(RoundedRectangle(cornerRadius: 14)).disabled(loading)

            Button("Already have an account? Sign in") { dismiss() }.padding(.top, 8)
            Spacer()
        }
        .padding(.horizontal, 28)
        .alert("Verify your email", isPresented: $sent) {
            Button("OK") { dismiss() }
        } message: { Text("We've sent a verification link to \(email.trimmed). Verify it, then sign in.") }
    }

    private func register() {
        guard email.trimmed.isValidEmail else { error = "Enter a valid email"; return }
        guard password.count >= 6 else { error = "Password must be at least 6 characters"; return }
        guard password == confirm else { error = "Passwords don't match"; return }
        error = nil; loading = true
        AuthService.register(email: email.trimmed, password: password) { e in
            loading = false
            if let e { error = e.localizedDescription } else { AuthService.signOut(); sent = true }
        }
    }
}
