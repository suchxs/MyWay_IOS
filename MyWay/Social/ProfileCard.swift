// Discord-style profile popout: tap a person's avatar in a chat (or roster) to see their banner,
// photo, name and @tag. Everything is live via ProfileStore, so an edit reflects while it's open.
import SwiftUI

struct ProfileCardTarget: Identifiable { let uid: String; let tag: String; var id: String { uid } }

struct ProfileCard: View {
    @Environment(\.dismiss) private var dismiss
    let uid: String
    let fallbackTag: String
    var onMessage: (() -> Void)? = nil          // shown only when it makes sense (e.g. from a group)
    @ObservedObject private var profiles = ProfileStore.shared

    private var tag: String { profiles.tag(uid).isEmpty ? fallbackTag : profiles.tag(uid) }
    private var name: String { profiles.name(uid) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                banner.frame(height: 120).frame(maxWidth: .infinity).clipped()
                AvatarCircle(photoBase64: profiles.photo(uid), tag: tag, size: 84)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 4))
                    .padding(.leading, 16).offset(y: 42)
            }
            VStack(alignment: .leading, spacing: 4) {
                Spacer().frame(height: 48)
                if !name.isEmpty { Text(name).font(.title2).bold() }
                Text("@\(tag)").foregroundColor(.secondary)
                if let onMessage {
                    Button { dismiss(); onMessage() } label: {
                        Label("Message", systemImage: "bubble.left.fill").bold().frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(Brand.teal).padding(.top, 12)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
            Spacer(minLength: 0)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { profiles.observe(uid); profiles.observeBanner(uid) }
    }

    @ViewBuilder private var banner: some View {
        if let img = Img.decode(profiles.banner(uid)) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            LinearGradient(colors: [Brand.tealBright, Brand.tealDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
