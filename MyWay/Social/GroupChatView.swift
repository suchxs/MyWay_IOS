// GroupChatActivity.kt → SwiftUI. Text + image + shared-pin messages, read receipts, roster/info sheet.
// Live-location cards and the in-chat trip controls are deferred with the Trips feature (see SETUP.md).
import SwiftUI
import PhotosUI
import FirebaseFirestore

struct GroupChatView: View {
    let group: TravelGroup
    let myUid: String
    let myTag: String

    @State private var messages: [GroupMessage] = []
    @State private var draft = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showInfo = false
    @State private var reg: ListenerRegistration?
    @State private var groupReg: ListenerRegistration?
    @State private var tripActive = false
    @ObservedObject private var trip = TripManager.shared

    var body: some View {
        VStack(spacing: 0) {
            tripBar
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { m in MessageRow(message: m, mine: m.from == myUid) }
                    }.padding(12)
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            composer
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { showInfo = true } label: { Image(systemName: "info.circle") } } }
        .sheet(isPresented: $showInfo) { GroupInfoSheet(gid: group.id, myUid: myUid) }
        .onAppear {
            tripActive = group.tripActive
            reg = Groups.listenMessages(group.id) { msgs in
                messages = msgs
                if let last = msgs.last { Groups.markRead(group.id, uid: myUid, ts: last.ts) }
            }
            groupReg = Groups.listenGroup(group.id) { g in tripActive = g?.tripActive ?? false }
        }
        .onDisappear { reg?.remove(); groupReg?.remove() }
        .onChange(of: photoItem) { item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
                Groups.sendImage(group.id, fromUid: myUid, fromTag: myTag, base64: Img.encode(img, maxDimension: 1024, quality: 0.6))
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

    // Trip controls (GroupChatActivity's Start Trip button + TripBar).
    @ViewBuilder private var tripBar: some View {
        let inThisTrip = trip.currentGid == group.id
        if tripActive || inThisTrip {
            HStack(spacing: 10) {
                Circle().fill(Color.red).frame(width: 10, height: 10)
                Text(inThisTrip ? "You're live • \(trip.members.count) sharing" : "Trip is live")
                    .font(.subheadline).bold()
                Spacer()
                if inThisTrip {
                    Button("Leave") { trip.leaveTrip() }
                        .buttonStyle(.borderedProminent).tint(Color(hex: 0xEF4444)).controlSize(.small)
                    Button("End") { trip.endTrip() }
                        .buttonStyle(.bordered).tint(Color(hex: 0xEF4444)).controlSize(.small)
                } else {
                    Button("Join") { trip.joinTrip(gid: group.id, groupName: group.name, tripActive: true) }
                        .buttonStyle(.borderedProminent).tint(Brand.teal).controlSize(.small)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Brand.teal.opacity(0.10))
        } else {
            Button { trip.joinTrip(gid: group.id, groupName: group.name, tripActive: false) } label: {
                Label("Start Trip", systemImage: "location.north.circle.fill").bold()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Brand.teal)
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }
}

private struct MessageRow: View {
    let message: GroupMessage
    let mine: Bool

    var body: some View {
        if message.system {
            Text(message.text).font(.caption).foregroundColor(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Color.gray.opacity(0.15)).clipShape(Capsule())
                .frame(maxWidth: .infinity)
        } else {
            HStack {
                if mine { Spacer() }
                VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                    if !mine { Text("@\(message.fromTag)").font(.caption2).foregroundColor(.secondary) }
                    bubble
                }
                if !mine { Spacer() }
            }
        }
    }

    @ViewBuilder private var bubble: some View {
        if let img = Img.decode(message.image) {
            Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else if message.pinLat != nil {
            HStack { Image(systemName: "mappin.circle.fill").foregroundColor(Brand.teal)
                Text(message.pinName.isEmpty ? "Shared location" : message.pinName).bold() }
                .padding(10).background(Brand.teal.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            Text(message.text)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(mine ? Brand.teal : Color.gray.opacity(0.18))
                .foregroundColor(mine ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct GroupInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let gid: String
    let myUid: String
    @State private var group: TravelGroup?
    @State private var reg: ListenerRegistration?

    var body: some View {
        NavigationStack {
            List {
                if let g = group {
                    Section("Members") {
                        ForEach(g.members, id: \.self) { uid in
                            HStack {
                                Text("@\(g.tagOf(uid))")
                                if g.isAdmin(uid) { Text("admin").font(.caption2).foregroundColor(.secondary) }
                                Spacer()
                                if g.owner == myUid, uid != myUid {
                                    Button(role: .destructive) { Groups.kickMember(gid, uid: uid) { _ in } } label: { Image(systemName: "person.badge.minus") }
                                }
                            }
                        }
                    }
                    Section {
                        Button(role: .destructive) { Groups.leaveGroup(gid, uid: myUid) { _ in }; dismiss() } label: { Text("Leave group") }
                    }
                }
            }
            .navigationTitle("Group info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onAppear { reg = Groups.listenGroup(gid) { group = $0 } }
            .onDisappear { reg?.remove() }
        }
    }
}
