// ProfileActivity.kt → SwiftUI. Edit name, @tag, avatar, banner — all auto-saved (no Save button) and
// pushed live to chats/groups via ProfileStore. Sign out; delete cloud data.
import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let uid: String

    private enum PickTarget { case photo, banner }

    @State private var profile = Profile()
    @State private var first = ""
    @State private var last = ""
    @State private var tag = ""
    @State private var banner = ""
    @State private var toast: String?
    @State private var loaded = false
    @State private var confirmDelete = false

    @State private var pickTarget: PickTarget = .photo
    @State private var showPicker = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var nameTask: Task<Void, Never>?
    @State private var tagTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                ProfileHeader(banner: banner, photo: profile.photo, tag: tag.isEmpty ? "?" : tag)
                    .listRowInsets(EdgeInsets())
                HStack {
                    Button { pickTarget = .photo; showPicker = true } label: { Label("Change photo", systemImage: "camera") }
                    Spacer()
                    Button { pickTarget = .banner; showPicker = true } label: { Label("Change banner", systemImage: "photo") }
                }.font(.subheadline).buttonStyle(.borderless)
            }
            Section("Name") {
                TextField("First name", text: $first).onChange(of: first) { _ in scheduleNameSave() }
                TextField("Last name", text: $last).onChange(of: last) { _ in scheduleNameSave() }
            }
            Section {
                HStack { Text("@"); TextField("tag", text: $tag).textInputAutocapitalization(.never).autocorrectionDisabled() }
                    .onChange(of: tag) { _ in scheduleTagSave() }
            } header: { Text("Handle") } footer: { Text("Changes save automatically.") }

            Section {
                Button("Sign out") { AuthService.signOut(); dismiss() }
                Button("Delete my account", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle("Profile")
        .alert("Delete your account?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                AuthService.deleteAccount(uid: uid, tagLower: Profiles.normalize(tag)) { err in
                    if let err { toast = err } else { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes your profile and sign-in account. This can't be undone.")
        }
        .photosPicker(isPresented: $showPicker, selection: $pickedItem, matching: .images)
        .overlay(alignment: .bottom) { if let toast { ToastView(toast) } }
        .onChange(of: pickedItem) { item in
            guard let item else { return }
            let target = pickTarget
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
                if target == .photo {
                    let b64 = Img.encode(img)
                    Profiles.updatePhoto(uid, base64: b64) { _ in }
                    state.setUserPhoto(uid, b64); ProfileStore.shared.setLocal(uid: uid, photo: b64); profile.photo = b64
                    TripManager.shared.updateMyPhoto(b64)   // refresh my live trip / share marker mid-session
                } else {
                    let b64 = Img.encode(img, maxDimension: 1024, quality: 0.6)   // wider than an avatar
                    Profiles.updateBanner(uid, base64: b64) { _ in }
                    banner = b64; ProfileStore.shared.setLocal(uid: uid, banner: b64)
                }
                pickedItem = nil
            }
        }
        .onAppear {
            guard !loaded else { return }; loaded = true
            Profiles.fetchProfile(uid) { p in
                guard let p else { return }
                profile = p; first = p.firstName; last = p.lastName; tag = p.tag
            }
            Profiles.fetchBanner(uid) { banner = $0 }
        }
    }

    private func scheduleNameSave() {
        nameTask?.cancel()
        nameTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            Profiles.updateName(uid, first: first, last: last) { _ in }
        }
    }

    private func scheduleTagSave() {
        tagTask?.cancel()
        tagTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            let norm = Profiles.normalize(tag)
            guard norm != Profiles.normalize(profile.tag), Profiles.formatError(norm) == nil else { return }
            Profiles.claimTag(uid, display: tag.trimmed) { res in
                switch res {
                case .success(let t): state.setUserTag(uid, t); ProfileStore.shared.setLocal(uid: uid, tag: t); profile.tag = t; toast = "Saved"
                case .taken: toast = "@\(norm) is taken"
                case .error(let m): toast = m
                }
            }
        }
    }
}
