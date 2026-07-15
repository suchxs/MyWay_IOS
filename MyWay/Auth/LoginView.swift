// LoginActivity.kt → SwiftUI. Email/password + Google + GitHub, forgot-password, verify-email prompt.
// Account-linking-on-collision (Android's pendingCredential dance) is deferred — see SETUP.md TODOs.
import SwiftUI

struct LoginView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var email = ""
    @State private var password = ""
    @State private var emailErr: String?
    @State private var passErr: String?
    @State private var error: String?
    @State private var loading = false
    @State private var showForgot = false
    @State private var showRegister = false
    @State private var verifyPrompt = false
    @State private var resetSentTo: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("MyWay").font(.system(size: 40, weight: .bold)).foregroundColor(Brand.tealDeep).padding(.top, 40)
                HStack(spacing: 4) {
                    Text("Find your way, together").foregroundColor(.secondary)
                    Image(systemName: "safari").foregroundColor(.secondary)
                }.padding(.bottom, 24)

                AuthTextField(title: "Email", text: $email, keyboard: .emailAddress, error: emailErr, enabled: !loading)
                AuthTextField(title: "Password", text: $password, isSecure: true, error: passErr, enabled: !loading)

                HStack {
                    Spacer()
                    Button("Forgot password?") { showForgot = true }.disabled(loading).font(.subheadline)
                }

                if let error { Text(error).foregroundColor(.red).font(.subheadline) }

                Button(action: login) {
                    if loading { ProgressView().tint(.white) }
                    else { Text("Sign in").fontWeight(.bold).foregroundColor(.white) }
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Brand.teal).clipShape(RoundedRectangle(cornerRadius: 14))
                .disabled(loading)

                Text("or continue with").foregroundColor(.secondary).font(.subheadline).padding(.vertical, 12)
                SocialButton(title: "Google", systemImage: "globe", action: google, enabled: !loading)
                SocialButton(title: "GitHub", systemImage: "chevron.left.forwardslash.chevron.right", action: github, enabled: !loading)

                HStack {
                    Text("Don't have an account?").foregroundColor(.secondary)
                    Button("Register") { showRegister = true }.fontWeight(.bold).disabled(loading)
                }.padding(.top, 16)
            }
            .padding(.horizontal, 28)
        }
        .background(Brand.background(scheme == .dark).ignoresSafeArea())
        .sheet(isPresented: $showRegister) { RegisterView() }
        .alert("Verify your email", isPresented: $verifyPrompt) {
            Button("Resend") { AuthService.resendVerification() }
            Button("OK", role: .cancel) {}
        } message: { Text("Please verify your email before signing in. Check your inbox for the verification link.") }
        .alert("Check your inbox", isPresented: .constant(resetSentTo != nil)) {
            Button("Got it") { resetSentTo = nil }
        } message: {
            Text("If an account exists for \(resetSentTo ?? ""), we've sent a link to reset the password. It expires in 1 hour.")
        }
        .sheet(isPresented: $showForgot) { forgotSheet }
    }

    private var forgotSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill").font(.largeTitle).foregroundColor(Brand.teal)
            Text("Reset your password").font(.title2).bold()
            Text("Enter the email you signed up with. We'll send you a link to set a new password.")
                .multilineTextAlignment(.center).foregroundColor(.secondary)
            AuthTextField(title: "Email", text: $email, keyboard: .emailAddress)
            Button("Send reset link") {
                showForgot = false; loading = true
                AuthService.sendPasswordReset(email.trimmed) { loading = false; resetSentTo = email.trimmed }
            }
            .frame(maxWidth: .infinity, minHeight: 50).background(Brand.teal).foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14)).disabled(!email.trimmed.isValidEmail)
            Button("Cancel") { showForgot = false }
        }
        .padding(28)
        .presentationDetents([.medium])
    }

    private func login() {
        emailErr = email.trimmed.isValidEmail ? nil : "Enter a valid email"
        passErr = password.isEmpty ? "Enter your password" : nil
        guard emailErr == nil, passErr == nil else { return }
        error = nil; loading = true
        AuthService.signIn(email: email.trimmed, password: password) { result in
            loading = false
            switch result {
            case .success(let verified): if !verified { AuthService.signOut(); verifyPrompt = true }
            case .failure(let e): error = e.localizedDescription
            }
        }
    }

    private func google() { error = nil; loading = true; AuthService.signInWithGoogle { loading = false; if let e = $0 { error = e.localizedDescription } } }
    private func github() { error = nil; loading = true; AuthService.signInWithGitHub { loading = false; if let e = $0 { error = e.localizedDescription } } }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
    var isValidEmail: Bool {
        range(of: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", options: .regularExpression) != nil
    }
}
