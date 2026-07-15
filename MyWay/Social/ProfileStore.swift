// Live cache of user profiles (photo, @tag, name), backed by users/{uid} snapshot listeners. Chat,
// group rosters, the drawer and map markers read from here so a profile edit propagates everywhere in
// real time — no re-open needed.
import SwiftUI
import FirebaseFirestore

@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published private(set) var photos: [String: String] = [:]
    @Published private(set) var tags: [String: String] = [:]
    @Published private(set) var names: [String: String] = [:]   // "First Last"
    private var regs: [String: ListenerRegistration] = [:]

    func observe(_ uids: [String]) { uids.forEach { observe($0) } }

    func observe(_ uid: String) {
        guard !uid.isEmpty, regs[uid] == nil else { return }
        regs[uid] = Firestore.firestore().collection("users").document(uid).addSnapshotListener { [weak self] d, _ in
            Task { @MainActor in
                guard let self, let d else { return }
                if let p = d.get("photo") as? String { self.photos[uid] = p }
                if let t = d.get("tag") as? String { self.tags[uid] = t }
                let name = "\(d.get("firstName") as? String ?? "") \(d.get("lastName") as? String ?? "")".trimmingCharacters(in: .whitespaces)
                self.names[uid] = name
            }
        }
    }

    func photo(_ uid: String) -> String { photos[uid] ?? "" }
    func tag(_ uid: String) -> String { tags[uid] ?? "" }

    /// Optimistic local update right after you change your own profile (before the listener echoes back).
    func setLocal(uid: String, photo: String? = nil, tag: String? = nil) {
        if let photo { photos[uid] = photo }
        if let tag { tags[uid] = tag }
    }
}
