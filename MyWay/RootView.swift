// Auth routing (LoginActivity.goToMain logic): signed-out → Login; signed-in-no-tag → Onboarding;
// signed-in-with-tag → Map home. Firebase's auth listener drives it so sign-out pops us back.
import SwiftUI
import FirebaseAuth

enum Route: Equatable { case loading, login, onboarding, main }

@MainActor
final class Router: ObservableObject {
    @Published var route: Route = .loading
    private var handle: AuthStateDidChangeListenerHandle?

    func start(_ state: AppState) {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            guard let user, user.isEmailVerified else {
                state.unbindUser(); InAppNotifier.shared.stop(); self.route = .login; return
            }
            state.bindUser(user.uid)
            FcmTokens.register(user.uid)
            TripManager.shared.bind(uid: user.uid, tag: state.userTag(user.uid), photo: state.userPhoto(user.uid))
            InAppNotifier.shared.start(user.uid)
            ProfileStore.shared.observe(user.uid)
            // Skip a Firestore read when we've cached the @tag; else fall back to fetchTag.
            if !state.userTag(user.uid).isEmpty { self.route = .main; return }
            Profiles.fetchTag(user.uid) { tag in
                Task { @MainActor in
                    if let tag { state.setUserTag(user.uid, tag); self.route = .main }
                    else { self.route = .onboarding }
                }
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var router = Router()

    var body: some View {
        Group   {
            switch router.route {
            case .loading:    ProgressView().tint(Brand.teal)
            case .login:      LoginView()
            case .onboarding: OnboardingView { router.route = .main }
            case .main:       MapHomeView()
            }
        }
        .overlay(alignment: .top) { if router.route == .main { NoticeBanner() } }
        .onAppear { router.start(state) }
    }
}
