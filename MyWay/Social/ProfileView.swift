// ProfileActivity.kt → SwiftUI. Edit name, @tag (rename), avatar; sign out; delete cloud data.
import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let uid: String

    @State private var profile = Profile()
    @State private var first = ""
    @State private var last = ""
    @State private var tag = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var toast: String?
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        AvatarCircle(photoBase64: profile.photo, tag: tag.isEmpty ? "?" : tag, size: 96)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.circle.fill").foregroundColor(Brand.teal).background(Circle().fill(.background))
                            }
                    }
                    Spacer()
                }
            }
            Section("Name") {
                TextField("First name", text: $first)
                TextField("Last name", text: $last)
            }
            Section("Handle") {
                HStack { Text("@"); TextField("tag", text: $tag).textInputAutocapitalization(.never).autocorrectionDisabled() }
            }
            Section {
                Button("Save changes") { save() }.tint(Brand.teal)
            }
            Section {
                Button("Sign out") { AuthService.signOut(); dismiss() }
                Button("Delete my data", role: .destructive) {
                    Profiles.deleteMyData(uid, tagLower: Profiles.normalize(tag)) { toast = $0 ?? "Deleted" }
                    AuthService.signOut(); dismiss()
                }
            }
        }
        .navigationTitle("Profile")
        .overlay(alignment: .bottom) { if let toast { ToastView(toast) } }
        .onChange(of: photoItem) { item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
                let b64 = Img.encode(img)
                Profiles.updatePhoto(uid, base64: b64) { _ in }
                state.setUserPhoto(uid, b64)
                profile.photo = b64
            }
        }
        .onAppear {
            guard !loaded else { return }; loaded = true
            Profiles.fetchProfile(uid) { p in
                guard let p else { return }
                profile = p; first = p.firstName; last = p.lastName; tag = p.tag
            }
        }
    }

    private func save() {
        Profiles.updateName(uid, first: first, last: last) { _ in }
        let norm = Profiles.normalize(tag)
        if norm != Profiles.normalize(profile.tag) {
            if let err = Profiles.formatError(norm) { toast = err; return }
            Profiles.claimTag(uid, display: tag.trimmed) { res in
                switch res {
                case .success(let t): state.setUserTag(uid, t); toast = "Saved"
                case .taken: toast = "@\(norm) is taken"
                case .error(let m): toast = m
                }
            }
        } else { toast = "Saved" }
    }
}
