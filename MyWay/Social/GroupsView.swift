// GroupsActivity.kt → SwiftUI. List my groups, create a new one from friends, open chat.
import SwiftUI
import FirebaseFirestore

struct GroupsView: View {
    let myUid: String
    let myTag: String
    @State private var groups: [TravelGroup] = []
    @State private var showCreate = false
    @State private var reg: ListenerRegistration?

    var body: some View {
        List(groups) { g in
            NavigationLink { GroupChatView(group: g, myUid: myUid, myTag: myTag) } label: {
                HStack {
                    AvatarCircle(photoBase64: g.photo, tag: g.name, size: 44)
                    VStack(alignment: .leading) {
                        HStack {
                            Text(g.name).bold()
                            if g.tripActive { Text("LIVE").font(.caption2).bold().foregroundColor(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(Color.red).clipShape(Capsule()) }
                        }
                        Text("\(g.members.count) members").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Groups")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { showCreate = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showCreate) { CreateGroupSheet(myUid: myUid, myTag: myTag) }
        .onAppear { reg = Groups.listenMyGroups(myUid) { groups = $0 } }
        .onDisappear { reg?.remove() }
    }
}

struct CreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let myUid: String
    let myTag: String
    @State private var name = ""
    @State private var friends: [UserHit] = []
    @State private var selected: Set<String> = []
    @State private var reg: ListenerRegistration?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Trip to…", text: $name) }
                Section("Add friends") {
                    ForEach(friends) { f in
                        Button {
                            if selected.contains(f.uid) { selected.remove(f.uid) } else { selected.insert(f.uid) }
                        } label: {
                            HStack {
                                Text("@\(f.tag)")
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
            .onAppear { reg = Friends.listenFriends(myUid) { friends = $0 } }
            .onDisappear { reg?.remove() }
        }
    }
}
