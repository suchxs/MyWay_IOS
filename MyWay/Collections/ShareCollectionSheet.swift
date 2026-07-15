// Pick a group or a friend to send a collection to — posts a collection card into that chat, which the
// recipient can tap to view every pin on the map and save it to their own collections.
import SwiftUI
import FirebaseFirestore

struct ShareCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let name: String
    let icon: String
    let pins: [SharedPin]
    let myUid: String
    let myTag: String

    @State private var groups: [TravelGroup] = []
    @State private var friends: [UserHit] = []
    @State private var friendsReg: ListenerRegistration?
    @State private var toast: String?
    @ObservedObject private var profiles = ProfileStore.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Text(icon.isEmpty ? "🗂️" : icon).font(.title)
                        VStack(alignment: .leading) {
                            Text(name.isEmpty ? "Collection" : name).bold()
                            Text("\(pins.count) place\(pins.count == 1 ? "" : "s")").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                if !friends.isEmpty {
                    Section("Friends") {
                        ForEach(friends) { f in
                            let tag = profiles.tag(f.uid).isEmpty ? f.tag : profiles.tag(f.uid)
                            Button { shareToFriend(f.uid, tag: tag) } label: {
                                HStack(spacing: 10) {
                                    AvatarCircle(photoBase64: profiles.photo(f.uid), tag: tag, size: 34)
                                    Text("@\(tag)").foregroundColor(.primary); Spacer()
                                    Image(systemName: "paperplane").foregroundColor(Brand.teal)
                                }
                            }
                        }
                    }
                }
                if !groups.isEmpty {
                    Section("Groups") {
                        ForEach(groups) { g in
                            Button { shareToGroup(g) } label: {
                                HStack(spacing: 10) {
                                    AvatarCircle(photoBase64: g.photo, tag: g.name, size: 34)
                                    Text(g.name).foregroundColor(.primary); Spacer()
                                    Image(systemName: "paperplane").foregroundColor(Brand.teal)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Share collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .overlay(alignment: .bottom) { if let toast { ToastView(toast) } }
            .onAppear {
                Groups.fetchMyGroups(myUid) { groups = $0 }
                friendsReg = Friends.listenFriends(myUid) { list in friends = list; ProfileStore.shared.observe(list.map { $0.uid }) }
            }
            .onDisappear { friendsReg?.remove() }
        }
    }

    private func shareToGroup(_ g: TravelGroup) {
        Groups.shareCollection(g.id, fromUid: myUid, fromTag: myTag, name: name, icon: icon, pins: pins)
        confirm("Shared to \(g.name)")
    }

    private func shareToFriend(_ uid: String, tag: String) {
        PrivateMessages.shareCollection(PrivateMessages.pairId(myUid, uid), fromUid: myUid, fromTag: myTag,
                                        otherUid: uid, otherTag: tag, name: name, icon: icon, pins: pins)
        confirm("Shared to @\(tag)")
    }

    private func confirm(_ msg: String) {
        toast = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { dismiss() }
    }
}
