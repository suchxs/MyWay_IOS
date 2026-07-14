// OnboardingActivity.kt → SwiftUI. Info pager + @tag claim on the last page.
import SwiftUI
import FirebaseAuth

struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    var onDone: () -> Void

    private struct Page: Identifiable { let id = UUID(); let emoji, title, body: String }
    private let pages = [
        Page(emoji: "🧭", title: "Welcome to MyWay", body: "Your group-travel companion. Share where you are, find your people, and plan the trip together — all on one map."),
        Page(emoji: "📍", title: "Map & waypoints", body: "Drop pins, save landmarks, and add notes. Organize places into collections you can revisit anytime."),
        Page(emoji: "🚗", title: "Directions & navigation", body: "Get turn-by-turn directions to any pin or landmark — drive, walk, bike, or transit — with live voice guidance."),
    ]

    @State private var index = 0
    @State private var tag = ""
    @State private var tagError: String?
    @State private var claiming = false

    private var tagPage: Int { pages.count }

    var body: some View {
        VStack {
            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.offset) { i, page in
                    infoPage(page).tag(i)
                }
                tagPageView.tag(tagPage)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            if index < tagPage {
                HStack {
                    Button("Skip") { withAnimation { index = tagPage } }.foregroundColor(.secondary)
                    Spacer()
                    Button("Next") { withAnimation { index += 1 } }
                        .fontWeight(.bold).padding(.horizontal, 24).padding(.vertical, 14)
                        .background(Brand.teal).foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                }.padding(.horizontal, 28).padding(.bottom, 20)
            }
        }
        .background(Brand.background(state.darkMode).ignoresSafeArea())
    }

    private func infoPage(_ page: Page) -> some View {
        VStack(spacing: 12) {
            Text(page.emoji).font(.system(size: 88))
            Text(page.title).font(.system(size: 28, weight: .bold)).foregroundColor(Brand.tealDeep)
            Text(page.body).multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal, 28)
        }
    }

    private var tagPageView: some View {
        VStack(spacing: 12) {
            Text("🏷️").font(.system(size: 72))
            Text("Claim your @tag").font(.system(size: 28, weight: .bold)).foregroundColor(Brand.tealDeep)
            Text("This is how friends find and add you. Pick something unique.")
                .multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal, 28)

            HStack {
                Text("@").foregroundColor(.secondary)
                TextField("Your tag", text: $tag)
                    .textInputAutocapitalization(.never).disableAutocorrection(true).disabled(claiming)
                    .onChange(of: tag) { tag = $0.filter { !$0.isWhitespace }; tagError = nil }
            }
            .padding(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(tagError == nil ? Color.gray.opacity(0.35) : .red))
            .padding(.horizontal, 28)
            if let tagError { Text(tagError).foregroundColor(.red).font(.footnote) }

            Button(action: claim) {
                if claiming { ProgressView().tint(.white) } else { Text("Get Started").fontWeight(.bold).foregroundColor(.white) }
            }
            .frame(maxWidth: .infinity, minHeight: 56).background(Brand.teal)
            .clipShape(RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 28)
            .disabled(claiming || tag.isEmpty)
        }
    }

    private func claim() {
        let display = tag.trimmed.hasPrefix("@") ? String(tag.trimmed.dropFirst()) : tag.trimmed
        let norm = Profiles.normalize(display)
        if let err = Profiles.formatError(norm) { tagError = err; return }
        guard let uid = Auth.auth().currentUser?.uid else { tagError = "You're not signed in"; return }
        claiming = true; tagError = nil
        Profiles.claimTag(uid, display: display) { res in
            claiming = false
            switch res {
            case .success(let t): state.setUserTag(uid, t); onDone()
            case .taken: tagError = "@\(norm) is already taken"
            case .error(let m): tagError = m
            }
        }
    }
}
