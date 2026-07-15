// FriendsActivity.kt → SwiftUI. Search by @tag, send/accept/decline requests, list + manage friends.
import SwiftUI
import FirebaseFirestore

struct FriendsView: View {
    let myUid: String
    let myTag: String

    @State private var query = ""
    @State private var results: [UserHit] = []
    @State private var friends: [UserHit] = []
    @State private var incoming: [FriendRequest] = []
    @State private var outgoing: [FriendRequest] = []
    @State private var toast: String?
    @State private var dmWith: UserHit?
    @State private var regs: [ListenerRegistration] = []
    @ObservedObject private var profiles = ProfileStore.shared

    var body: some View {
        List {
            Section {
                TextField("Find friends by @tag", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onChange(of: query) { q in
                        Friends.search(q, myUid: myUid) { results = $0 }
                    }
                ForEach(results) { hit in
                    HStack {
                        AvatarCircle(photoBase64: hit.photo, tag: hit.tag, size: 36)
                        VStack(alignment: .leading) {
                            Text("@\(hit.tag)").bold()
                            if !hit.fullName.isEmpty { Text(hit.fullName).font(.caption).foregroundColor(.secondary) }
                        }
                        Spacer()
                        if friends.contains(where: { $0.uid == hit.uid }) {
                            Text("Friends").font(.caption).foregroundColor(.secondary)
                        } else if outgoing.contains(where: { $0.toUid == hit.uid }) {
                            Text("Requested").font(.caption).foregroundColor(.secondary)
                        } else {
                            Button("Add") { Friends.sendRequest(myUid: myUid, myTag: myTag, target: hit) { toast = $0 ?? "Request sent" } }
                                .buttonStyle(.borderedProminent).tint(Brand.teal)
                        }
                    }
                }
            } header: { Text("Search") }

            if !incoming.isEmpty {
                Section("Requests") {
                    ForEach(incoming) { req in
                        HStack {
                            AvatarCircle(photoBase64: profiles.photo(req.fromUid), tag: req.fromTag, size: 36)
                            Text("@\(req.fromTag)").bold()
                            Spacer()
                            Button("Accept") { Friends.accept(req) { toast = $0 } }.tint(Brand.teal).buttonStyle(.bordered)
                            Button("Decline") { Friends.deleteRequest(req) { _ in } }.tint(.red).buttonStyle(.bordered)
                        }
                    }
                }
            }

            Section("Friends (\(friends.count))") {
                ForEach(friends) { f in
                    HStack {
                        AvatarCircle(photoBase64: profiles.photo(f.uid), tag: profiles.tag(f.uid).isEmpty ? f.tag : profiles.tag(f.uid), size: 36)
                        Text("@\(profiles.tag(f.uid).isEmpty ? f.tag : profiles.tag(f.uid))").bold()
                        if f.isClose { Image(systemName: "star.fill").foregroundColor(.yellow).font(.caption) }
                        Spacer()
                    }
                    .swipeActions {
                        Button(role: .destructive) { Friends.removeFriend(myUid: myUid, otherUid: f.uid) { _ in } } label: { Label("Remove", systemImage: "trash") }
                        Button { Friends.setCloseFriend(myUid: myUid, otherUid: f.uid, isClose: !f.isClose) { _ in } } label: {
                            Label(f.isClose ? "Unstar" : "Close", systemImage: "star")
                        }.tint(.yellow)
                        Button { dmWith = f } label: { Label("Message", systemImage: "bubble.left") }.tint(Brand.teal)
                    }
                }
            }
        }
        .navigationTitle("Friends")
        .sheet(item: $dmWith) { f in
            NavigationStack {
                PrivateChatView(chatId: PrivateMessages.pairId(myUid, f.uid), myUid: myUid, myTag: myTag,
                                otherUid: f.uid, otherTag: f.tag)
            }
        }
        .overlay(alignment: .bottom) { if let toast { ToastView(toast) } }
        .onAppear {
            regs = [
                Friends.listenFriends(myUid) { list in friends = list; ProfileStore.shared.observe(list.map { $0.uid }) },
                Friends.listenIncoming(myUid) { list in incoming = list; ProfileStore.shared.observe(list.map { $0.fromUid }) },
                Friends.listenOutgoing(myUid) { outgoing = $0 },
            ]
        }
        .onDisappear { regs.forEach { $0.remove() }; regs = [] }
    }
}

struct ToastView: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial).clipShape(Capsule()).padding(.bottom, 24)
    }
}
