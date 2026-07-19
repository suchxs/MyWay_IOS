// Unified inbox (Messenger-style): group chats + 1-on-1 DMs in one list, newest first. The + button
// starts either a DM (pick a friend) or a new group. Names/photos/previews are live via ProfileStore
// (DMs) and the groups listener. Opening a row goes to the group or private chat.
import SwiftUI
import PhotosUI
import FirebaseFirestore
import GoogleMaps

// One row in the unified inbox — a group or a DM, normalised so they render + sort together.
struct Conversation: Identifiable {
    enum Kind { case group(TravelGroup); case dm(chat: PrivateChat, otherUid: String, tag: String) }
    let id: String
    let kind: Kind
    let title: String
    let photo: String
    let preview: String
    let ts: Int64
    let tripActive: Bool
    let unread: Bool
    let pinned: Bool
    let archived: Bool
    let muted: Bool
    var isGroup: Bool { if case .group = kind { return true }; return false }
}

struct MessagesView: View {
    let myUid: String
    let myTag: String
    @State private var chats: [PrivateChat] = []
    @State private var groups: [TravelGroup] = []
    @State private var showNewMenu = false
    @State private var showNewDM = false
    @State private var showNewGroup = false
    @State private var chatReg: ListenerRegistration?
    @State private var groupReg: ListenerRegistration?
    @State private var tab = 0   // 0 = All, 1 = Groups
    @State private var showArchived = false
    @ObservedObject private var profiles = ProfileStore.shared
    @ObservedObject private var app = AppState.shared

    private var conversations: [Conversation] {
        let dms = chats.map { c -> Conversation in
            let other = c.otherUid(myUid)
            let tag = profiles.tag(other).isEmpty ? c.otherTag(myUid) : profiles.tag(other)
            return Conversation(id: "p:\(c.id)", kind: .dm(chat: c, otherUid: other, tag: tag),
                                title: "@\(tag)", photo: profiles.photo(other),
                                preview: c.lastMsg, ts: c.lastTs, tripActive: false, unread: c.isUnread(myUid),
                                pinned: c.isPinned(myUid), archived: c.isArchived(myUid), muted: c.isMuted(myUid))
        }
        let grps = groups.map { g in
            Conversation(id: "g:\(g.id)", kind: .group(g), title: g.name, photo: g.photo,
                         preview: g.lastMsg.isEmpty ? "\(g.members.count) members" : g.lastMsg,
                         ts: g.lastTs, tripActive: g.tripActive, unread: g.isUnread(myUid),
                         pinned: g.isPinned(myUid), archived: g.isArchived(myUid), muted: g.isMuted(myUid))
        }
        return (dms + grps)
            .filter { $0.archived == showArchived && (tab == 0 || $0.isGroup) }
            // Pinned float to the top, then newest first (matches Android's inbox ordering).
            .sorted { ($0.pinned ? 1 : 0, $0.ts) > ($1.pinned ? 1 : 0, $1.ts) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !showArchived { tabBar }
            if conversations.isEmpty {
                Spacer()
                Text(showArchived ? "No archived conversations." : "No conversations yet.")
                    .foregroundColor(.secondary).multilineTextAlignment(.center).padding(32)
                Spacer()
            } else {
                List(conversations) { conv in
                    NavigationLink { destination(conv) } label: { row(conv) }
                        .contextMenu { contextActions(conv) }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(showArchived ? "Archived" : "Messages")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showArchived.toggle() } label: {
                    Image(systemName: showArchived ? "tray.full" : "archivebox")
                }
            }
            ToolbarItem(placement: .primaryAction) { Button { showNewMenu = true } label: { Image(systemName: "square.and.pencil") } }
        }
        .confirmationDialog("Start a conversation", isPresented: $showNewMenu, titleVisibility: .visible) {
            Button("Message a friend") { showNewDM = true }
            Button("Create a group") { showNewGroup = true }
        }
        .sheet(isPresented: $showNewDM) { NewMessageSheet(myUid: myUid, myTag: myTag) }
        .sheet(isPresented: $showNewGroup) { CreateGroupSheet(myUid: myUid, myTag: myTag) }
        .onAppear {
            chatReg = PrivateMessages.listenMyChats(myUid) { list in
                chats = list; ProfileStore.shared.observe(list.map { $0.otherUid(myUid) })
            }
            groupReg = Groups.listenMyGroups(myUid) { list in
                groups = list; list.forEach { ProfileStore.shared.observe($0.members) }
            }
        }
        .onDisappear { chatReg?.remove(); groupReg?.remove() }
    }

    // Messenger-style All / Groups tabs, each with a red unread badge.
    private var tabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tabButton("All", index: 0, badge: app.unreadAllCount)
                tabButton("Groups", index: 1, badge: app.unreadGroupsCount)
            }
            Divider()
        }
        .background(.bar)
    }

    private func tabButton(_ title: String, index: Int, badge: Int) -> some View {
        let selected = tab == index
        return Button { tab = index } label: {
            VStack(spacing: 8) {
                HStack(spacing: 5) {
                    Text(title).fontWeight(.semibold)
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color(hex: 0xEF4444)).clipShape(Capsule())
                    }
                }
                .foregroundColor(selected ? Brand.teal : .secondary)
                .padding(.top, 10)
                Rectangle().fill(selected ? Brand.teal : .clear).frame(height: 2.5)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // Long-press actions on a conversation row (pin / archive / mute / delete), Messenger-style.
    @ViewBuilder private func contextActions(_ conv: Conversation) -> some View {
        let gid = conv.isGroup ? String(conv.id.dropFirst(2)) : nil
        let cid = !conv.isGroup ? String(conv.id.dropFirst(2)) : nil
        Button { setFlag(conv, "pinned", !conv.pinned) } label: {
            Label(conv.pinned ? "Unpin" : "Pin", systemImage: conv.pinned ? "pin.slash" : "pin")
        }
        Button { setFlag(conv, "archived", !conv.archived) } label: {
            Label(conv.archived ? "Unarchive" : "Archive", systemImage: conv.archived ? "tray.and.arrow.up" : "archivebox")
        }
        Button { setFlag(conv, "muted", !conv.muted) } label: {
            Label(conv.muted ? "Unmute" : "Mute", systemImage: conv.muted ? "bell" : "bell.slash")
        }
        if case .dm(_, let otherUid, _) = conv.kind {
            Button(role: .destructive) { Profiles.blockUser(myUid, targetUid: otherUid) } label: {
                Label("Block user", systemImage: "hand.raised")
            }
        }
        Button(role: .destructive) {
            if let gid { Groups.leaveGroup(gid, uid: myUid) { _ in } }
            else if let cid { PrivateMessages.deleteChat(cid, uid: myUid) }
        } label: {
            Label(conv.isGroup ? "Leave group" : "Delete chat", systemImage: "trash")
        }
    }

    private func setFlag(_ conv: Conversation, _ field: String, _ value: Bool) {
        let id = String(conv.id.dropFirst(2))   // strip "g:" / "p:" prefix
        if conv.isGroup { Groups.updateMetadata(id, uid: myUid, field: field, value: value) }
        else { PrivateMessages.updateMetadata(id, uid: myUid, field: field, value: value) }
    }

    @ViewBuilder private func destination(_ conv: Conversation) -> some View {
        switch conv.kind {
        case .group(let g): GroupChatView(group: g, myUid: myUid, myTag: myTag)
        case .dm(let c, let other, let tag): PrivateChatView(chatId: c.id, myUid: myUid, myTag: myTag, otherUid: other, otherTag: tag)
        }
    }

    private func row(_ conv: Conversation) -> some View {
        HStack(spacing: 12) {
            AvatarCircle(photoBase64: conv.photo, tag: conv.title.replacingOccurrences(of: "@", with: ""), size: 46)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if case .group = conv.kind { Image(systemName: "person.3.fill").font(.caption2).foregroundColor(.secondary) }
                    Text(conv.title).fontWeight(conv.unread ? .heavy : .bold).lineLimit(1)
                    if conv.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundColor(Brand.tealDeep) }
                    if conv.muted { Image(systemName: "bell.slash.fill").font(.caption2).foregroundColor(.secondary) }
                    if conv.tripActive {
                        Text("LIVE").font(.caption2).bold().foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Color.red).clipShape(Capsule())
                    }
                }
                Text(conv.preview.isEmpty ? "No messages yet" : conv.preview)
                    .font(.caption).fontWeight(conv.unread ? .semibold : .regular)
                    .foregroundColor(conv.unread ? .primary : .secondary).lineLimit(1)
            }
            if conv.unread { Spacer(); Circle().fill(Brand.teal).frame(width: 9, height: 9) }
        }
    }
}

struct NewMessageSheet: View {
    @Environment(\.dismiss) private var dismiss
    let myUid: String
    let myTag: String
    @State private var friends: [UserHit] = []
    @State private var reg: ListenerRegistration?
    @ObservedObject private var profiles = ProfileStore.shared

    var body: some View {
        NavigationStack {
            List(friends) { f in
                NavigationLink {
                    PrivateChatView(chatId: PrivateMessages.pairId(myUid, f.uid), myUid: myUid, myTag: myTag, otherUid: f.uid, otherTag: f.tag)
                } label: {
                    HStack { AvatarCircle(photoBase64: profiles.photo(f.uid), tag: f.tag, size: 36); Text("@\(f.tag)").bold(); Spacer() }
                }
            }
            .navigationTitle("New message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { reg = Friends.listenFriends(myUid) { list in friends = list; ProfileStore.shared.observe(list.map { $0.uid }) } }
            .onDisappear { reg?.remove() }
        }
    }
}

struct PrivateChatView: View {
    let chatId: String
    let myUid: String
    let myTag: String
    let otherUid: String
    let otherTag: String

    @State private var messages: [GroupMessage] = []
    @State private var chat: PrivateChat?
    @State private var draft = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showInfo = false
    @State private var liveViewer: LiveTarget?
    @State private var pinViewer: PinTarget?
    @State private var cardTarget: ProfileCardTarget?
    @State private var collOffer: CollectionOffer?
    @State private var reg: ListenerRegistration?
    @State private var chatReg: ListenerRegistration?
    @ObservedObject private var trip = TripManager.shared
    @ObservedObject private var profiles = ProfileStore.shared

    private var liveTags: [String: String] {
        [myUid: profiles.tag(myUid).isEmpty ? myTag : profiles.tag(myUid),
         otherUid: profiles.tag(otherUid).isEmpty ? otherTag : profiles.tag(otherUid)]
    }

    // Unsend — soft tombstone; refresh the inbox preview when it was the newest message.
    private func deleteMsg(_ m: GroupMessage) {
        PrivateMessages.unsendMessage(chatId, mid: m.id, isLast: messages.last?.id == m.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatMessageList(messages: messages, myUid: myUid, photos: profiles.photos,
                            reads: chat?.reads ?? [:], tags: liveTags,
                            onOpenPin: { m in if let la = m.pinLat, let ln = m.pinLng { pinViewer = PinTarget(lat: la, lng: ln, name: m.pinName, note: m.pinNote) } },
                            onOpenLive: { m in liveViewer = LiveTarget(uid: m.liveFrom, name: "@\(m.fromTag)") },
                            onOpenCollection: { m in collOffer = CollectionOffer(name: m.collName, icon: m.collIcon, pins: m.collPins) },
                            onDelete: { m in deleteMsg(m) },
                            onCommitEdit: { m, t in
                                PrivateMessages.editMessage(chatId, mid: m.id, text: t,
                                                            newPreview: messages.last?.id == m.id ? t : nil)
                            },
                            onTapUser: { uid, tag in cardTarget = ProfileCardTarget(uid: uid, tag: tag) })
            HStack(spacing: 8) {
                PhotosPicker(selection: $photoItem, matching: .images) { Image(systemName: "photo").font(.title3) }
                TextField("Message @\(otherTag)", text: $draft, axis: .vertical).lineLimit(1...4)
                    .padding(8).background(Color.gray.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 18))
                Button {
                    PrivateMessages.sendMessage(chatId, fromUid: myUid, fromTag: myTag, otherUid: otherUid, otherTag: otherTag, text: draft)
                    draft = ""
                } label: { Image(systemName: "arrow.up.circle.fill").font(.title).foregroundColor(Brand.teal) }
                    .disabled(draft.trimmed.isEmpty)
            }.padding(10).background(.ultraThinMaterial)
        }
        .navigationTitle("@\(otherTag)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Share my live location with this person for 1 hour (LiveShare); tap again to stop.
                Button {
                    if trip.sharingLive { trip.stopLiveShare() }
                    else {
                        trip.startLiveShare(toUid: otherUid, toTag: otherTag)
                        PrivateMessages.postLiveShare(chatId, fromUid: myUid, fromTag: myTag, otherUid: otherUid, otherTag: otherTag)
                    }
                } label: {
                    Image(systemName: trip.sharingLive ? "location.slash.fill" : "location.fill")
                        .foregroundColor(trip.sharingLive ? Color(hex: 0xEF4444) : Brand.teal)
                }
            }
            ToolbarItem(placement: .primaryAction) { Button { showInfo = true } label: { Image(systemName: "info.circle") } }
        }
        .sheet(isPresented: $showInfo) { DMInfoSheet(otherUid: otherUid, otherTag: otherTag, messages: messages) }
        .sheet(item: $liveViewer) { t in LiveViewerSheet(uid: t.uid, name: t.name) }
        .sheet(item: $pinViewer) { PinViewerSheet(pin: $0) }
        .sheet(item: $cardTarget) { t in ProfileCard(uid: t.uid, fallbackTag: t.tag) }
        .sheet(item: $collOffer) { CollectionViewerSheet(offer: $0) }
        .onAppear {
            InAppNotifier.shared.activeChatKey = chatId
            ProfileStore.shared.observe([myUid, otherUid])
            reg = PrivateMessages.listenMessages(chatId) { msgs in
                messages = msgs
                if let last = msgs.last { PrivateMessages.markRead(chatId, uid: myUid, ts: last.ts) }
            }
            chatReg = PrivateMessages.listenChat(chatId) { chat = $0 }
        }
        .onDisappear { reg?.remove(); chatReg?.remove(); InAppNotifier.shared.activeChatKey = nil }
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { photoItem = nil; return }
                PrivateMessages.sendImage(chatId, fromUid: myUid, fromTag: myTag, otherUid: otherUid, otherTag: otherTag,
                                          base64: Img.encode(img, maxDimension: 1000, quality: 0.5))
                photoItem = nil
            }
        }
    }
}

struct LiveTarget: Identifiable { let uid: String; let name: String; var id: String { uid } }

// LiveLocationActivity.kt → SwiftUI. Real-time map of EVERYONE currently sharing with me (the tapped
// person + anyone else in the group/thread) plus my own position — each rendered with their profile photo.
struct LiveViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let uid: String        // the person whose card you tapped (used to centre + title)
    let name: String
    @State private var shares: [TripMember] = []   // others sharing with me (from live_shares/visibleTo)
    @State private var loaded = false
    @State private var camera: GMSCameraPosition?
    @State private var reg: ListenerRegistration?
    @ObservedObject private var profiles = ProfileStore.shared
    @ObservedObject private var trip = TripManager.shared    // am I currently sharing?
    @StateObject private var myLoc = LocationManager()       // my own live position while the sheet is open

    private var myUid: String { AuthService.currentUid ?? "" }

    // My own avatar marker (profile photo) — follows my GPS live, like everyone else's.
    private var meMarker: TripMember? {
        guard let c = myLoc.location?.coordinate ?? AppState.shared.lastLocation else { return nil }
        return TripMember(uid: myUid, tag: profiles.tag(myUid).ifEmptyThen(AppState.shared.userTag(myUid)),
                          photo: profiles.photo(myUid).ifEmptyThen(AppState.shared.userPhoto(myUid)),
                          lat: c.latitude, lng: c.longitude)
    }
    // Include myself when I'm sharing OR when I tapped my own card (so I always see myself on it).
    private var includeMe: Bool { trip.sharingLive || uid == myUid }
    private var allMarkers: [TripMember] { shares + ((includeMe ? meMarker : nil).map { [$0] } ?? []) }

    var body: some View {
        NavigationStack {
            Group {
                if !allMarkers.isEmpty {
                    VStack(spacing: 0) {
                        // myUid stays "" here so my own marker renders too (the map hides only its own myUid).
                        GoogleMapView(places: [], pinHue: 0, pinIcon: "", pencilGlyph: "",
                                      dark: AppState.shared.darkMode, showPersonal: false,
                                      liveShares: allMarkers, camera: $camera,
                                      onTapMarker: { _ in }, onLongPress: { _ in })
                            .ignoresSafeArea(edges: .bottom)
                        Text("🔴 Live · \(allMarkers.count) sharing").bold().padding()
                    }
                } else if !loaded {
                    ProgressView()
                } else {
                    Text("\(name) is no longer sharing their location.").foregroundColor(.secondary).padding(32)
                }
            }
            .navigationTitle("Live location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear {
                myLoc.start()
                reg = LiveShare.listenVisible(myUid) { states in
                    shares = states.compactMap { s in
                        guard let lat = s.lat, let lng = s.lng else { return nil }
                        return TripMember(uid: s.uid, tag: profiles.tag(s.uid).ifEmptyThen(s.tag),
                                          photo: profiles.photo(s.uid).ifEmptyThen(s.photo), lat: lat, lng: lng)
                    }
                    loaded = true
                    focusCamera()
                }
            }
            .onChange(of: myLoc.location) { _ in focusCamera() }   // my card → centre once GPS lands
            .onDisappear { reg?.remove(); myLoc.stop() }
        }
    }

    // Centre on the tapped person; if that's me (my own card), centre on my position.
    private func focusCamera() {
        guard camera == nil else { return }
        let focus = (uid == myUid ? meMarker : shares.first(where: { $0.uid == uid })) ?? shares.first ?? meMarker
        if let f = focus, let lat = f.lat, let lng = f.lng {
            camera = GMSCameraPosition(latitude: lat, longitude: lng, zoom: 15)
        }
    }
}

private extension String {
    func ifEmptyThen(_ fallback: String) -> String { isEmpty ? fallback : self }
}

struct PinTarget: Identifiable { let lat, lng: Double; let name, note: String; var id: String { "\(lat),\(lng)" } }

// Shared-pin viewer: a chat pin dropped into a message, shown on the map so you can see where it is.
struct PinViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let pin: PinTarget
    @State private var camera: GMSCameraPosition?

    var body: some View {
        NavigationStack {
            GoogleMapView(places: [SavedPlace(key: locationKey(pin.lat, pin.lng), lat: pin.lat, lng: pin.lng,
                                              name: pin.name, note: pin.note)],
                          pinHue: 200, pinIcon: "📍", pencilGlyph: "📍",
                          dark: AppState.shared.darkMode, showPersonal: true,
                          camera: $camera, onTapMarker: { _ in }, onLongPress: { _ in })
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(pin.name.isEmpty ? "Shared location" : pin.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                .onAppear { camera = GMSCameraPosition(latitude: pin.lat, longitude: pin.lng, zoom: 16) }
        }
    }
}

struct CollectionOffer: Identifiable { let name, icon: String; let pins: [SharedPin]; var id: String { "\(name)-\(pins.count)" } }

// Viewer for a collection shared in chat: shows every pin on the map + a one-tap save into your places.
struct CollectionViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let offer: CollectionOffer
    @State private var camera: GMSCameraPosition?
    @State private var saved = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GoogleMapView(places: offer.pins.map { SavedPlace(key: locationKey($0.lat, $0.lng), lat: $0.lat, lng: $0.lng, name: $0.name, note: $0.note) },
                              pinHue: 280, pinIcon: "📍", pencilGlyph: "📍",
                              dark: AppState.shared.darkMode, showPersonal: true,
                              camera: $camera, onTapMarker: { _ in }, onLongPress: { _ in })
                    .ignoresSafeArea(edges: .bottom)
                Button {
                    AppState.shared.importSharedCollection(name: offer.name, icon: offer.icon, pins: offer.pins)
                    saved = true
                } label: {
                    Label(saved ? "Saved to your collections" : "Save to my collections",
                          systemImage: saved ? "checkmark.circle.fill" : "square.and.arrow.down").bold().frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(Brand.teal).disabled(saved).padding()
            }
            .navigationTitle("\(offer.icon.isEmpty ? "🗂️" : offer.icon) \(offer.name.isEmpty ? "Collection" : offer.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear { if let f = offer.pins.first { camera = GMSCameraPosition(latitude: f.lat, longitude: f.lng, zoom: 12) } }
        }
    }
}

struct DMInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let otherUid: String
    let otherTag: String
    let messages: [GroupMessage]
    @ObservedObject private var profiles = ProfileStore.shared

    private var recentImages: [GroupMessage] { messages.filter { !$0.image.isEmpty }.suffix(12).reversed() }
    private var liveTag: String { profiles.tag(otherUid).isEmpty ? otherTag : profiles.tag(otherUid) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 0) {
                        // Live photo + banner — a profile edit by the other person reflects here immediately.
                        ProfileHeader(banner: profiles.banner(otherUid), photo: profiles.photo(otherUid), tag: liveTag)
                        if !profiles.name(otherUid).isEmpty {
                            Text(profiles.name(otherUid)).font(.title3).bold().frame(maxWidth: .infinity)
                        }
                        Text("@\(liveTag)").font(.subheadline).foregroundColor(.secondary).frame(maxWidth: .infinity)
                    }.listRowInsets(EdgeInsets())
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
            }
            .navigationTitle("Chat info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onAppear { profiles.observe(otherUid); profiles.observeBanner(otherUid) }
        }
    }
}
