// NotificationHub.kt → SwiftUI, extended. A foreground listener that shows in-app banners for: new
// group messages, new DMs, trip starts, and incoming friend requests. Seeds "last seen" on the first
// snapshot so it never notifies for backlog, and suppresses the chat you're currently viewing.
import SwiftUI
import FirebaseFirestore

@MainActor
final class InAppNotifier: ObservableObject {
    static let shared = InAppNotifier()

    struct Notice: Identifiable, Equatable { let id = UUID(); let icon: String; let title: String; let subtitle: String }
    @Published var current: Notice?
    var activeChatKey: String?      // gid or chatId currently open → don't notify for it

    private var uid = ""
    private var groupsReg: ListenerRegistration?
    private var dmReg: ListenerRegistration?
    private var friendReqReg: ListenerRegistration?
    private var msgRegs: [String: ListenerRegistration] = [:]   // gid/chatId → latest-message listener
    private var lastMsgId: [String: String] = [:]
    private var seeded: Set<String> = []
    private var tripActive: [String: Bool] = [:]
    private var groupNames: [String: String] = [:]
    private var seededReqs = false
    private var knownReqs: Set<String> = []
    private var dismiss: Task<Void, Never>?

    func start(_ uid: String) {
        guard !uid.isEmpty, uid != self.uid else { return }
        stop(); self.uid = uid

        groupsReg = Groups.listenMyGroups(uid) { [weak self] groups in Task { @MainActor in self?.syncGroups(groups) } }
        dmReg = PrivateMessages.listenMyChats(uid) { [weak self] chats in Task { @MainActor in self?.syncChats(chats) } }
        friendReqReg = Friends.listenIncoming(uid) { [weak self] reqs in Task { @MainActor in self?.syncRequests(reqs) } }
    }

    func stop() {
        groupsReg?.remove(); dmReg?.remove(); friendReqReg?.remove()
        msgRegs.values.forEach { $0.remove() }; msgRegs.removeAll()
        lastMsgId.removeAll(); seeded.removeAll(); tripActive.removeAll(); groupNames.removeAll()
        knownReqs.removeAll(); seededReqs = false; uid = ""; current = nil
    }

    // ── Groups (messages + trip start) ─────────────────────────────────────────────
    private func syncGroups(_ groups: [TravelGroup]) {
        let ids = Set(groups.map { $0.id })
        for g in groups {
            groupNames[g.id] = g.name
            if tripActive[g.id] == false, g.tripActive, activeChatKey != g.id {
                show("figure.walk.circle.fill", "Trip started", "in \(g.name)")
            }
            tripActive[g.id] = g.tripActive
            if msgRegs["g:\(g.id)"] == nil { attachMessages(key: "g:\(g.id)", collection: Firestore.firestore().collection("groups").document(g.id).collection("messages"), title: g.name, isGroup: true, contextId: g.id) }
        }
        for gid in Set(tripActive.keys).subtracting(ids) {
            msgRegs["g:\(gid)"]?.remove(); msgRegs["g:\(gid)"] = nil; tripActive[gid] = nil
        }
    }

    private func syncChats(_ chats: [PrivateChat]) {
        for c in chats where msgRegs["p:\(c.id)"] == nil {
            let title = "@\(c.otherTag(uid))"
            attachMessages(key: "p:\(c.id)", collection: Firestore.firestore().collection("private_chats").document(c.id).collection("messages"), title: title, isGroup: false, contextId: c.id)
        }
    }

    private func attachMessages(key: String, collection: CollectionReference, title: String, isGroup: Bool, contextId: String) {
        msgRegs[key] = collection.order(by: "ts", descending: true).limit(to: 1).addSnapshotListener { [weak self] snap, _ in
            Task { @MainActor in
                guard let self, let doc = snap?.documents.first else { return }
                if !self.seeded.contains(key) { self.lastMsgId[key] = doc.documentID; self.seeded.insert(key); return }
                if self.lastMsgId[key] == doc.documentID { return }
                self.lastMsgId[key] = doc.documentID
                let from = doc.get("from") as? String ?? ""
                if from == self.uid || from == "system" { return }
                if self.activeChatKey == contextId { return }
                let who = doc.get("fromTag") as? String ?? ""
                let preview = self.preview(doc)
                let subtitle = isGroup ? "@\(who): \(preview)" : preview
                self.show(isGroup ? "bubble.left.and.bubble.right.fill" : "bubble.left.fill", title, subtitle)
            }
        }
    }

    private func syncRequests(_ reqs: [FriendRequest]) {
        let ids = Set(reqs.map { $0.id })
        if !seededReqs { knownReqs = ids; seededReqs = true; return }
        for r in reqs where !knownReqs.contains(r.id) {
            show("person.crop.circle.badge.plus", "Friend request", "from @\(r.fromTag)")
        }
        knownReqs = ids
    }

    private func preview(_ doc: DocumentSnapshot) -> String {
        if !((doc.get("image") as? String ?? "").isEmpty) { return "📷 Photo" }
        if !((doc.get("liveFrom") as? String ?? "").isEmpty) { return "🔴 Live location" }
        if doc.get("pinLat") != nil { return "📍 " + ((doc.get("pinName") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Location") }
        return doc.get("text") as? String ?? ""
    }

    private func show(_ icon: String, _ title: String, _ subtitle: String) {
        current = Notice(icon: icon, title: title, subtitle: subtitle)
        dismiss?.cancel()
        dismiss = Task { try? await Task.sleep(nanoseconds: 4_000_000_000); current = nil }
    }
}

/// Transient top banner shown app-wide (RootView).
struct NoticeBanner: View {
    @ObservedObject var notifier = InAppNotifier.shared
    var body: some View {
        VStack {
            if let n = notifier.current {
                HStack(spacing: 12) {
                    Image(systemName: n.icon).font(.title3).foregroundColor(Brand.teal)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(n.title).font(.subheadline).bold()
                        Text(n.subtitle).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                    Spacer()
                }
                .padding(12).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 8).padding(.horizontal, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { notifier.current = nil }
            }
            Spacer()
        }
        .animation(.spring(response: 0.35), value: notifier.current)
    }
}
