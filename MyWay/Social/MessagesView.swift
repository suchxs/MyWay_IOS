// MessagesActivity + PrivateChatActivity → SwiftUI. DM inbox + 1-on-1 chat with avatars, read receipts,
// and an info sheet (the other person + recent images). Start a chat from the inbox or a friend.
import SwiftUI
import PhotosUI
import FirebaseFirestore
import GoogleMaps

struct MessagesView: View {
    let myUid: String
    let myTag: String
    @State private var chats: [PrivateChat] = []
    @State private var showNew = false
    @State private var reg: ListenerRegistration?
    @ObservedObject private var profiles = ProfileStore.shared

    var body: some View {
        List(chats) { chat in
            let other = chat.otherUid(myUid)
            let tag = profiles.tag(other).isEmpty ? chat.otherTag(myUid) : profiles.tag(other)
            NavigationLink {
                PrivateChatView(chatId: chat.id, myUid: myUid, myTag: myTag, otherUid: other, otherTag: tag)
            } label: {
                HStack {
                    AvatarCircle(photoBase64: profiles.photo(other), tag: tag, size: 44)
                    VStack(alignment: .leading) {
                        Text("@\(tag)").bold()
                        Text(chat.lastMsg).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .navigationTitle("Messages")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { showNew = true } label: { Image(systemName: "square.and.pencil") } } }
        .sheet(isPresented: $showNew) { NewMessageSheet(myUid: myUid, myTag: myTag) }
        .onAppear {
            reg = PrivateMessages.listenMyChats(myUid) { list in
                chats = list
                ProfileStore.shared.observe(list.map { $0.otherUid(myUid) })
            }
        }
        .onDisappear { reg?.remove() }
    }
}

struct NewMessageSheet: View {
    @Environment(\.dismiss) private var dismiss
    let myUid: String
    let myTag: String
    @State private var friends: [UserHit] = []
    @State private var reg: ListenerRegistration?

    var body: some View {
        NavigationStack {
            List(friends) { f in
                NavigationLink {
                    PrivateChatView(chatId: PrivateMessages.pairId(myUid, f.uid), myUid: myUid, myTag: myTag, otherUid: f.uid, otherTag: f.tag)
                } label: {
                    HStack { AvatarCircle(photoBase64: f.photo, tag: f.tag, size: 36); Text("@\(f.tag)").bold(); Spacer() }
                }
            }
            .navigationTitle("New message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { reg = Friends.listenFriends(myUid) { friends = $0 } }
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
    @State private var reg: ListenerRegistration?
    @State private var chatReg: ListenerRegistration?
    @ObservedObject private var trip = TripManager.shared
    @ObservedObject private var profiles = ProfileStore.shared

    private var liveTags: [String: String] {
        [myUid: profiles.tag(myUid).isEmpty ? myTag : profiles.tag(myUid),
         otherUid: profiles.tag(otherUid).isEmpty ? otherTag : profiles.tag(otherUid)]
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatMessageList(messages: messages, myUid: myUid, photos: profiles.photos,
                            reads: chat?.reads ?? [:], tags: liveTags,
                            onOpenLive: { m in liveViewer = LiveTarget(uid: m.liveFrom, name: "@\(m.fromTag)") })
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

// LiveLocationActivity.kt → SwiftUI. Follows live_shares/{uid} in real time on a mini map.
struct LiveViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let uid: String
    let name: String
    @State private var state: LiveShare.State?
    @State private var loaded = false
    @State private var camera: GMSCameraPosition?
    @State private var reg: ListenerRegistration?

    var body: some View {
        NavigationStack {
            Group {
                if let s = state, s.active, let lat = s.lat, let lng = s.lng {
                    VStack(spacing: 0) {
                        GoogleMapView(places: [], pinHue: 0, pinIcon: "", pencilGlyph: "", dark: false, showPersonal: false,
                                      liveShares: [TripMember(uid: uid, tag: name.replacingOccurrences(of: "@", with: ""), photo: s.photo, lat: lat, lng: lng)],
                                      camera: $camera, onTapMarker: { _ in }, onLongPress: { _ in })
                            .ignoresSafeArea(edges: .bottom)
                        Text("🔴 Live · \(minutesLeft(s.expiresAt)) min left").bold().padding()
                    }
                } else if !loaded {
                    ProgressView()
                } else {
                    Text("\(name) is no longer sharing their location.").foregroundColor(.secondary).padding(32)
                }
            }
            .navigationTitle("\(name) · live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear {
                reg = LiveShare.listen(uid) { s in
                    state = s; loaded = true
                    if let s, let lat = s.lat, let lng = s.lng { camera = GMSCameraPosition(latitude: lat, longitude: lng, zoom: 16) }
                }
            }
            .onDisappear { reg?.remove() }
        }
    }

    private func minutesLeft(_ expiresAtMillis: TimeInterval) -> Int {
        max(0, Int((expiresAtMillis - Date().timeIntervalSince1970 * 1000) / 60000))
    }
}

struct DMInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let otherUid: String
    let otherTag: String
    let messages: [GroupMessage]
    @State private var photo = ""
    @State private var banner = ""

    private var recentImages: [GroupMessage] { messages.filter { !$0.image.isEmpty }.suffix(12).reversed() }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 0) {
                        ProfileHeader(banner: banner, photo: photo, tag: otherTag)
                        Text("@\(otherTag)").font(.title3).bold().frame(maxWidth: .infinity)
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
            .onAppear {
                Profiles.fetchProfile(otherUid) { photo = $0?.photo ?? "" }
                Profiles.fetchBanner(otherUid) { banner = $0 }
            }
        }
    }
}
