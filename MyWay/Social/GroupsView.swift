// Create a group from friends — reached via the + in the unified Messages inbox (groups + DMs are fused).
import SwiftUI
import FirebaseFirestore

struct CreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let myUid: String
    let myTag: String
    @State private var name = ""
    @State private var friends: [UserHit] = []
    @State private var selected: Set<String> = []
    @State private var reg: ListenerRegistration?
    @ObservedObject private var profiles = ProfileStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Trip to…", text: $name) }
                Section("Add friends") {
                    ForEach(friends) { f in
                        Button {
                            if selected.contains(f.uid) { selected.remove(f.uid) } else { selected.insert(f.uid) }
                        } label: {
                            HStack(spacing: 10) {
                                AvatarCircle(photoBase64: profiles.photo(f.uid), tag: profiles.tag(f.uid).isEmpty ? f.tag : profiles.tag(f.uid), size: 32)
                                Text("@\(profiles.tag(f.uid).isEmpty ? f.tag : profiles.tag(f.uid))")
                                Spacer()
                                if selected.contains(f.uid) { Image(systemName: "checkmark").foregroundColor(Brand.teal) }
                            }
                        }.tint(.primary)
                    }
                }
            }
            .navigationTitle("New group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let picked = friends.filter { selected.contains($0.uid) }
                        Groups.createGroup(owner: myUid, ownerTag: myTag, name: name, friends: picked) { _ in dismiss() }
                    }.disabled(name.trimmed.isEmpty)
                }
            }
            .onAppear { reg = Friends.listenFriends(myUid) { friends = $0; ProfileStore.shared.observe($0.map { $0.uid }) } }
            .onDisappear { reg?.remove() }
        }
    }
}
