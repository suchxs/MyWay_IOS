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
    @State private var showSchedule = false
    @State private var showQueue = false
    @State private var groupPlan: TripPlan?       // this group's shared plan (listened even when not live)
    @State private var planReg: ListenerRegistration?
    @State private var liveViewer: LiveTarget?
    @State private var pinViewer: PinTarget?
    @State private var cardTarget: ProfileCardTarget?
    @State private var dmTarget: ProfileCardTarget?
    @State private var collOffer: CollectionOffer?
    @State private var reg: ListenerRegistration?
    @State private var groupReg: ListenerRegistration?
    @State private var callParticipants: [String] = []   // who's in the group call now (empty = none)
    @State private var callReg: ListenerRegistration?
    @ObservedObject private var trip = TripManager.shared
    @ObservedObject private var profiles = ProfileStore.shared
    @ObservedObject private var callMgr = CallManager.shared

    private var g: TravelGroup { liveGroup ?? group }
    private var liveTags: [String: String] { g.tags.merging(profiles.tags) { _, live in live } }

    var body: some View {
        VStack(spacing: 0) {
            callBanner
            tripBar
            ChatMessageList(messages: messages, myUid: myUid, photos: profiles.photos,
                            reads: g.reads, tags: liveTags,
                            onOpenPin: { m in if let la = m.pinLat, let ln = m.pinLng { pinViewer = PinTarget(lat: la, lng: ln, name: m.pinName, note: m.pinNote) } },
                            onOpenLive: { m in liveViewer = LiveTarget(uid: m.liveFrom, name: "@\(liveTags[m.from] ?? m.fromTag)") },
                            onOpenCollection: { m in collOffer = CollectionOffer(name: m.collName, icon: m.collIcon, pins: m.collPins) },
                            onDelete: { m in Groups.unsendMessage(group.id, mid: m.id, isLast: messages.last?.id == m.id) },
                            onCommitEdit: { m, t in
                                Groups.editMessage(group.id, mid: m.id, text: t, newPreview: messages.last?.id == m.id ? t : nil)
                            },
                            onTapUser: { uid, tag in if uid != myUid { cardTarget = ProfileCardTarget(uid: uid, tag: tag) } })
            composer
        }
        .sheet(item: $liveViewer) { t in LiveViewerSheet(uid: t.uid, name: t.name) }
        .sheet(item: $pinViewer) { PinViewerSheet(pin: $0) }
        .sheet(item: $collOffer) { CollectionViewerSheet(offer: $0) }
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { CallManager.shared.startGroupCall(gid: group.id, name: g.name, photo: g.photo, video: false) } label: {
                    // Green + badge when a call is already in progress, so members know to join.
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "phone.fill").foregroundColor(callParticipants.isEmpty ? Brand.teal : .green)
                        if !callParticipants.isEmpty {
                            Text("\(callParticipants.count)").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                                .padding(3).background(Circle().fill(.green)).offset(x: 8, y: -8)
                        }
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { CallManager.shared.startGroupCall(gid: group.id, name: g.name, photo: g.photo, video: true) } label: {
                    Image(systemName: "video.fill").foregroundColor(callParticipants.isEmpty ? Brand.teal : .green)
                }
            }
            ToolbarItem(placement: .primaryAction) { Button { showInfo = true } label: { Image(systemName: "info.circle") } }
        }
        .sheet(isPresented: $showInfo) {
            GroupInfoSheet(initialGroup: g, myUid: myUid, myTag: myTag, messages: messages, photos: profiles.photos)
        }
        .sheet(isPresented: $showSchedule) {
            ScheduleTripSheet(group: group, myUid: myUid, myTag: myTag,
                              onStartNow: { trip.joinTrip(gid: group.id, groupName: group.name, tripActive: false) },
                              onScheduled: { showQueue = true })
        }
        .sheet(isPresented: $showQueue) {
            PlanView(gid: group.id, actorUid: myUid, actorTag: myTag, tripPins: trip.pins)
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
            planReg = Trip.listenPlan(group.id) { groupPlan = $0 }
            callReg = Calls.listenGroupCall(group.id) { callParticipants = $0 }
        }
        .onDisappear { reg?.remove(); groupReg?.remove(); planReg?.remove(); callReg?.remove(); InAppNotifier.shared.activeChatKey = nil }
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

    // Shown when a group call is live and I'm not already in it — one tap to join.
    @ViewBuilder private var callBanner: some View {
        if !callParticipants.isEmpty && callMgr.phase == .idle {
            HStack(spacing: 10) {
                Image(systemName: "video.fill").foregroundColor(.white)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Group call in progress").font(.subheadline).bold().foregroundColor(.white)
                    Text("\(callParticipants.count) in call").font(.caption).foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                Button { CallManager.shared.startGroupCall(gid: group.id, name: g.name, photo: g.photo, video: true) } label: {
                    Text("Join").bold().foregroundColor(.green)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Capsule().fill(.white))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.green)
        }
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
        } else if let at = g.tripScheduledAt {
            scheduledBanner(at)
        } else {
            Button { showSchedule = true } label: {
                Label("Start Trip", systemImage: "location.north.circle.fill").bold().frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(Brand.teal).padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    @ViewBuilder private func scheduledBanner(_ at: Date) -> some View {
        let going = g.tripGoing.contains(myUid)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock").foregroundColor(Brand.tealDeep)
                Text("Trip scheduled for \(tripStamp(at))").font(.subheadline).bold()
                Spacer()
            }
            // Attendance — who's coming, plus my own toggle.
            HStack(spacing: 8) {
                if !g.tripGoing.isEmpty {
                    AvatarStack(uids: g.tripGoing, profiles: profiles)
                    Text("\(g.tripGoing.count) going").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button(going ? "Going ✓" : "I'm going") { Trip.setGoing(group.id, uid: myUid, going: !going) }
                    .buttonStyle(.bordered).tint(going ? Brand.teal : .secondary).controlSize(.small)
            }
            HStack(spacing: 8) {
                Button { showQueue = true } label: {
                    Label("Activities" + (groupPlan.map { $0.items.isEmpty ? "" : " (\($0.items.count))" } ?? ""),
                          systemImage: "list.bullet")
                }.buttonStyle(.bordered).tint(Brand.teal).controlSize(.small)
                Spacer()
                Button("Cancel", role: .destructive) { Trip.endSession(group.id) { _ in } }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }.padding(.horizontal, 14).padding(.vertical, 10).background(Brand.teal.opacity(0.10))
    }
}

/// A row of overlapping member avatars (used for the attendance list).
struct AvatarStack: View {
    let uids: [String]
    @ObservedObject var profiles: ProfileStore
    var body: some View {
        HStack(spacing: -8) {
            ForEach(uids.prefix(5), id: \.self) { uid in
                AvatarCircle(photoBase64: profiles.photo(uid), tag: profiles.tag(uid), size: 24)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
            }
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
    @State private var showPhotoPicker = false
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
                            Button(group.photo.isEmpty ? "Add group photo" : "Change photo") { showPhotoPicker = true }
                                .foregroundColor(Brand.tealDeep)
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
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { photoItem = nil; return }
                    Groups.updatePhoto(group.id, base64: Img.encode(img, maxDimension: 512, quality: 0.7)) { _ in }
                    photoItem = nil   // reset so picking again re-fires
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
