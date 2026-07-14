// ProfileCard.kt → SwiftUI. Discord-style banner (image or teal gradient) with the avatar overlapping
// its lower edge, plus a popup profile card loaded by uid (friend search / member tap).
import SwiftUI

struct ProfileHeader: View {
    let banner: String
    let photo: String
    let tag: String
    var bannerHeight: CGFloat = 96
    var avatar: CGFloat = 72

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let img = Img.decode(banner) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [Brand.tealBright, Brand.tealDeep], startPoint: .leading, endPoint: .trailing)
                }
            }
            .frame(height: bannerHeight).frame(maxWidth: .infinity).clipped()

            AvatarCircle(photoBase64: photo, tag: tag, size: avatar)
                .padding(4).background(Circle().fill(.background))
                .offset(x: 16, y: avatar / 2)
        }
        .padding(.bottom, avatar / 2)
    }
}

/// Popup profile card loaded by uid — banner + avatar + name/@tag, with an optional Message action.
struct ProfileCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let uid: String
    let tagHint: String
    var myUid: String = ""
    var myTag: String = ""
    var onMessage: ((UserHit) -> Void)? = nil

    @State private var profile = Profile()
    @State private var banner = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ProfileHeader(banner: banner, photo: profile.photo, tag: profile.tag.isEmpty ? tagHint : profile.tag)
                VStack(alignment: .leading, spacing: 4) {
                    let name = profile.fullName
                    if !name.isEmpty { Text(name).font(.title2).bold() }
                    Text("@\(profile.tag.isEmpty ? tagHint : profile.tag)").foregroundColor(.secondary)
                }.padding(.horizontal, 20)

                if let onMessage {
                    Button {
                        onMessage(UserHit(uid: uid, tag: profile.tag.isEmpty ? tagHint : profile.tag))
                        dismiss()
                    } label: { Label("Message", systemImage: "bubble.left.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(Brand.teal).padding(20)
                }
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear {
                Profiles.fetchProfile(uid) { if let p = $0 { profile = p } }
                Profiles.fetchBanner(uid) { banner = $0 }
            }
        }
        .presentationDetents([.medium])
    }
}

private extension Profile { var fullName: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) } }
