// GroupChatActivity.kt → SwiftUI. Text + image + shared-pin messages with avatars, read receipts, and a
// group-info sheet (photo, recent images, member roster with roles). Live via Firestore listeners.
import SwiftUI
import PhotosUI
import FirebaseFirestore

struct GroupChatView: View {
    let group: TravelGroup
    let myUid: String
    let myTag: String

    @State private var messages: [GroupMessage] = []
    @State private var liveGroup: TravelGroup?
    @State private var draft = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showInfo = false
    @State private var liveViewer: LiveTarget?
    @State private var pinViewer: PinTarget?
    @State private var cardTarget: ProfileCardTarget?
    @State private var dmTarget: ProfileCardTarget?
    @State private var reg: ListenerRegistration?
    @State private var groupReg: ListenerRegistration?
    @ObservedObject private var trip = TripManager.shared
    @ObservedObject private var profiles = ProfileStore.shared

    private var g: TravelGroup { liveGroup ?? group }
    private var liveTags: [String: String] { g.tags.merging(profiles.tags) { _, live in live } }

    var body: some View {
        VStack(spacing: 0) {
            tripBar
            ChatMessageList(messages: messages, myUid: myUid, photos: profiles.photos,
                            reads: g.reads, tags: liveTags,
                            onOpenPin: { m in if let la = m.pinLat, let ln = m.pinLng { pinViewer = PinTarget(lat: la, lng: ln, name: m.pinName, note: m.pinNote) } },
                            onOpenLive: { m in liveViewer = LiveTarget(uid: m.liveFrom, name: "@\(liveTags[m.from] ?? m.fromTag)") },
                            onDelete: { m in Groups.unsendMessage(group.id, mid: m.id, isLast: messages.last?.id == m.id) },
                            onCommitEdit: { m, t in
                                Groups.editMessage(group.id, mid: m.id, text: t, newPreview: messages.last?.id == m.id ? t : nil)
                            },
                            onTapUser: { uid, tag in if uid != myUid { cardTarget = ProfileCardTarget(uid: uid, tag: tag) } })
            composer
        }
        .sheet(item: $liveViewer) { t in LiveViewerSheet(uid: t.uid, name: t.name) }
        .sheet(item: $pinViewer) { PinViewerSheet(pin: $0) }
        .sheet(item: $cardTarget) { t in
            ProfileCard(uid: t.uid, fallbackTag: t.tag, onMessage: { dmTarget = t })
        }
        .sheet(item: $dmTarget) { t in
            NavigationStack {
                PrivateChatView(chatId: PrivateMessages.pairId(myUid, t.uid), myUid: myUid, myTag: myTag,
                                otherUid: t.uid, otherTag: t.tag)
            }
        }
        .navigationTitle(g.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { showInfo = true } label: { Image(systemName: "info.circle") } } }
        .sheet(isPresented: $showInfo) {
            GroupInfoSheet(initialGroup: g, myUid: myUid, myTag: myTag, messages: messages, photos: profiles.photos)
        }
        .onAppear {
            InAppNotifier.shared.activeChatKey = group.id
            reg = Groups.listenMessages(group.id) { msgs in
                messages = msgs
                if let last = msgs.last { Groups.markRead(group.id, uid: myUid, ts: last.ts) }
            }
            groupReg = Groups.listenGroup(group.id) { grp in
                liveGroup = grp
                if let grp { ProfileStore.shared.observe(grp.members) }   // live avatars + @tags
            }
        }
        .onDisappear { reg?.remove(); groupReg?.remove(); InAppNotifier.shared.activeChatKey = nil }
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { photoItem = nil; return }
                Groups.sendImage(group.id, fromUid: myUid, fromTag: myTag, base64: Img.encode(img, maxDimension: 1000, quality: 0.5))
                photoItem = nil   // reset so picking the same photo again re-fires
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $photoItem, matching: .images) { Image(systemName: "photo").font(.title3) }
            TextField("Message", text: $draft, axis: .vertical).lineLimit(1...4)
                .padding(8).background(Color.gray.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 18))
            Button {
                Groups.sendMessage(group.id, fromUid: myUid, fromTag: myTag, text: draft); draft = ""
            } label: { Image(systemName: "arrow.up.circle.fill").font(.title).foregroundColor(Brand.teal) }
                .disabled(draft.trimmed.isEmpty)
        }
        .padding(10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder private var tripBar: some View {
        let inThisTrip = trip.currentGid == group.id
        if g.tripActive || inThisTrip {
            HStack(spacing: 10) {
                Circle().fill(Color.red).frame(width: 10, height: 10)
                Text(inThisTrip ? "You're live • \(trip.members.count) sharing" : "Trip is live").font(.subheadline).bold()
                Spacer()
                if inThisTrip {
                    Button("Leave") { trip.leaveTrip() }.buttonStyle(.borderedProminent).tint(Color(hex: 0xEF4444)).controlSize(.small)
                    Button("End") { trip.endTrip() }.buttonStyle(.bordered).tint(Color(hex: 0xEF4444)).controlSize(.small)
                } else {
                    Button("Join") { trip.joinTrip(gid: group.id, groupName: group.name, tripActive: true) }
                        .buttonStyle(.borderedProminent).tint(Brand.teal).controlSize(.small)
                }
            }.padding(.horizontal, 14).padding(.vertical, 8).background(Brand.teal.opacity(0.10))
        } else {
            Button { trip.joinTrip(gid: group.id, groupName: group.name, tripActive: false) } label: {
                Label("Start Trip", systemImage: "location.north.circle.fill").bold().frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(Brand.teal).padding(.horizontal, 14).padding(.vertical, 8)
        }
    }
}

struct GroupInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initialGroup: TravelGroup
    let myUid: String
    let myTag: String
    let messages: [GroupMessage]
    let photos: [String: String]
    @ObservedObject private var profiles = ProfileStore.shared

    @State private var liveGroup: TravelGroup?
    @State private var groupReg: ListenerRegistration?
    @State private var photoItem: PhotosPickerItem?
    @State private var showAdd = false
    @State private var confirmDelete = false

    // Live group doc so role changes (promote/demote/kick) reflect in real time.
    private var group: TravelGroup { liveGroup ?? initialGroup }
    private var iAmOwner: Bool { myUid == group.owner }
    private var iAmAdmin: Bool { group.isAdmin(myUid) }
    private var recentImages: [GroupMessage] { messages.filter { !$0.image.isEmpty }.suffix(12).reversed() }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        AvatarCircle(photoBase64: group.photo, tag: group.name, size: 96)
                        if iAmAdmin {
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Text(group.photo.isEmpty ? "Add group photo" : "Change photo").foregroundColor(Brand.tealDeep)
                            }
                        }
                        Text(group.name).font(.title3).bold()
                    }.frame(maxWidth: .infinity)
                }

                if !recentImages.isEmpty {
                    Section("Recent images") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(recentImages) { m in
                                    if let img = Img.decode(m.image) {
                                        Image(uiImage: img).resizable().scaledToFill()
                                            .frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Members (\(group.members.count))") {
                    ForEach(group.members, id: \.self) { uid in memberRow(uid) }
                    if iAmAdmin { Button { showAdd = true } label: { Label("Add member", systemImage: "person.badge.plus") } }
                }

                Section {
                    if iAmOwner {
                        Button("Delete group", role: .destructive) { confirmDelete = true }
                    } else {
                        Button("Leave group", role: .destructive) { Groups.leaveGroup(group.id, uid: myUid) { _ in }; dismiss() }
                    }
                }
            }
            .navigationTitle("Group info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showAdd) { AddMemberSheet(group: group, myUid: myUid) }
            .alert("Delete group?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { Groups.deleteGroup(group.id); dismiss() }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: photoItem) { item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
                    Groups.updatePhoto(group.id, base64: Img.encode(img, maxDimension: 512, quality: 0.7)) { _ in }
                }
            }
            .onAppear {
                groupReg = Groups.listenGroup(initialGroup.id) { g in
                    if let g { liveGroup = g; ProfileStore.shared.observe(g.members) }
                }
            }
            .onDisappear { groupReg?.remove() }
        }
    }

    private func memberRow(_ uid: String) -> some View {
        let isOwner = uid == group.owner
        let isAdmin = group.isAdmin(uid)
        let canKick = iAmAdmin && !isOwner && uid != myUid
        let liveTag = profiles.tag(uid).isEmpty ? group.tagOf(uid) : profiles.tag(uid)
        return HStack {
            AvatarCircle(photoBase64: profiles.photo(uid), tag: liveTag, size: 36)
            VStack(alignment: .leading) {
                Text("@\(liveTag)").bold()
                if isOwner { Text("Owner").font(.caption2).foregroundColor(.secondary) }
                else if isAdmin { Text("Admin").font(.caption2).foregroundColor(.secondary) }
            }
            Spacer()
            if iAmOwner, !isOwner {
                Button(isAdmin ? "Demote" : "Make admin") {
                    Groups.setAdmin(group.id, uid: uid, makeAdmin: !isAdmin) { _ in }
                }.font(.caption).tint(Brand.tealDeep)
            }
            if canKick {
                Button(role: .destructive) { Groups.kickMember(group.id, uid: uid) { _ in } } label: { Image(systemName: "person.badge.minus") }
            }
        }
    }
}

struct AddMemberSheet: View {
    @Environment(\.dismiss) private var dismiss
    let group: TravelGroup
    let myUid: String
    @State private var friends: [UserHit] = []
    @State private var reg: ListenerRegistration?
    @ObservedObject private var profiles = ProfileStore.shared

    var body: some View {
        NavigationStack {
            List(friends.filter { !group.members.contains($0.uid) }) { f in
                Button { Groups.addMember(group.id, friend: f) { _ in }; dismiss() } label: {
                    HStack { AvatarCircle(photoBase64: profiles.photo(f.uid), tag: f.tag, size: 34); Text("@\(f.tag)").bold(); Spacer() }
                }
            }
            .navigationTitle("Add member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { reg = Friends.listenFriends(myUid) { list in friends = list; ProfileStore.shared.observe(list.map { $0.uid }) } }
            .onDisappear { reg?.remove() }
        }
    }
}
