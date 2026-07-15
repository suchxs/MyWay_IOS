// Shared chat rendering (GroupChatActivity's MessageList/MessageBubble/ReadReceipts) used by both group
// chat and DMs: avatars on the last bubble of a run, tap-for-details (time + seen-by), and Messenger-style
// read-receipt avatars under the newest message each member has seen.
import SwiftUI

private let burstGap: Int64 = 15 * 60 * 1000   // stamp the start of a conversation burst

struct ChatMessageList: View {
    let messages: [GroupMessage]
    let myUid: String
    let photos: [String: String]
    let reads: [String: Int64]          // uid → newest ts they've seen (empty for chats without receipts)
    let tags: [String: String]
    var onOpenPin: (GroupMessage) -> Void = { _ in }
    var onOpenLive: (GroupMessage) -> Void = { _ in }
    var onDelete: (GroupMessage) -> Void = { _ in }
    var onCommitEdit: (GroupMessage, String) -> Void = { _, _ in }
    var onTapUser: (String, String) -> Void = { _, _ in }   // tap a sender's avatar → their profile card

    @State private var selectedId: String?
    @State private var editing: GroupMessage?
    @State private var editDraft = ""

    // Each other member's receipt hangs on the newest message they've seen.
    private var receipts: [String: [String]] {
        var byMessage: [String: [String]] = [:]
        for (uid, ts) in reads where uid != myUid {
            guard let seen = messages.last(where: { !$0.system && $0.ts <= ts }) else { continue }
            byMessage[seen.id, default: []].append(uid)
        }
        return byMessage
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { i, m in
                        let prev = i > 0 ? messages[i - 1] : nil
                        let next = i < messages.count - 1 ? messages[i + 1] : nil
                        VStack(spacing: 0) {
                            if prev == nil || m.ts - prev!.ts > burstGap { TimeSeparator(ts: m.ts) }
                            MessageBubble(m: m, mine: m.from == myUid, photo: photos[m.from] ?? "",
                                          tag: tags[m.from] ?? m.fromTag,
                                          showAvatar: next == nil || next!.from != m.from,
                                          onTap: { selectedId = selectedId == m.id ? nil : m.id },
                                          onOpenPin: onOpenPin, onOpenLive: onOpenLive,
                                          onEdit: { editDraft = m.text; editing = m },
                                          onDelete: { onDelete(m) },
                                          onTapUser: { onTapUser(m.from, tags[m.from] ?? m.fromTag) })
                            if selectedId == m.id, !m.system { detailsRow(m) }
                            if let seenBy = receipts[m.id] { readReceipts(seenBy) }
                        }.id(m.id)
                    }
                }.padding(.horizontal, 12).padding(.vertical, 8)
            }
            .onChange(of: messages.count) { _ in if let l = messages.last { withAnimation { proxy.scrollTo(l.id, anchor: .bottom) } } }
            .onAppear { if let l = messages.last { proxy.scrollTo(l.id, anchor: .bottom) } }
            .alert("Edit message", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                TextField("Message", text: $editDraft)
                Button("Save") { if let m = editing { onCommitEdit(m, editDraft) }; editing = nil }
                Button("Cancel", role: .cancel) { editing = nil }
            }
        }
    }

    private func detailsRow(_ m: GroupMessage) -> some View {
        let seenBy = reads.filter { (uid, ts) in uid != m.from && uid != myUid && ts >= m.ts }.keys
        let seen = seenBy.isEmpty ? "Not seen yet" : "Seen by " + seenBy.map { "@\(tags[$0] ?? "someone")" }.joined(separator: ", ")
        return HStack {
            if m.from == myUid { Spacer() }
            Text("\(stamp(m.ts)) · \(seen)").font(.caption2).foregroundColor(.secondary)
            if m.from != myUid { Spacer() }
        }.padding(.horizontal, 34).padding(.top, 2)
    }

    private func readReceipts(_ uids: [String]) -> some View {
        HStack(spacing: 2) {
            Spacer()
            ForEach(uids, id: \.self) { uid in AvatarCircle(photoBase64: photos[uid] ?? "", tag: tags[uid] ?? "?", size: 14) }
        }.padding(.top, 2)
    }
}

private struct TimeSeparator: View {
    let ts: Int64
    var body: some View {
        Text(stamp(ts)).font(.caption2).bold().foregroundColor(.secondary.opacity(0.7))
            .frame(maxWidth: .infinity).padding(.vertical, 8)
    }
}

private struct MessageBubble: View {
    let m: GroupMessage
    let mine: Bool
    let photo: String
    var tag: String = ""
    let showAvatar: Bool
    var onTap: () -> Void
    var onOpenPin: (GroupMessage) -> Void
    var onOpenLive: (GroupMessage) -> Void = { _ in }
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    var onTapUser: () -> Void = {}

    var body: some View {
        if m.system {
            Text(m.text).font(.caption).foregroundColor(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 4)
        } else {
            HStack(alignment: .bottom, spacing: 6) {
                if !mine {
                    if showAvatar {
                        AvatarCircle(photoBase64: photo, tag: tag.isEmpty ? m.fromTag : tag, size: 28)
                            .onTapGesture { onTapUser() }
                    } else { Color.clear.frame(width: 28, height: 28) }
                }
                if mine { Spacer(minLength: 40) }
                bubble
                if !mine { Spacer(minLength: 40) }
            }.padding(.vertical, 2)
        }
    }

    private var isPin: Bool { m.pinLat != nil && m.pinLng != nil }
    private var isLive: Bool { !m.liveFrom.isEmpty }
    private var isImage: Bool { !m.image.isEmpty }
    private var isText: Bool { !isImage && !isPin && !isLive }   // only plain text is editable

    @ViewBuilder private var bubble: some View {
        if m.unsent {
            // Tombstone — the message was unsent but stays in place (Messenger-style), muted + outlined.
            HStack(spacing: 6) {
                Image(systemName: "slash.circle").font(.caption)
                Text(mine ? "You unsent a message" : "@\(tag.isEmpty ? m.fromTag : tag) unsent a message").italic()
            }
            .font(.subheadline).foregroundColor(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.35), lineWidth: 1))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if !mine { Text("@\(tag.isEmpty ? m.fromTag : tag)").font(.caption2).bold().foregroundColor(Brand.tealDeep)
                    .padding(.leading, isImage ? 4 : 0).onTapGesture { onTapUser() } }
                content
            }
            .foregroundColor(mine ? .white : .primary)
            // Images get no coloured bubble (that teal/cyan box behind photos was the bug); text/cards do.
            .padding(.horizontal, isImage ? 0 : 12).padding(.vertical, isImage ? 0 : 8)
            .background(isImage ? Color.clear : (mine ? Brand.teal : Color.gray.opacity(0.18)))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture { if isLive { onOpenLive(m) } else if isPin { onOpenPin(m) } else if !isImage { onTap() } }
            // Hold a message to edit (text only) or unsend it — Messenger-style, your own messages only.
            .contextMenu {
                if mine {
                    if isText { Button { onEdit() } label: { Label("Edit", systemImage: "pencil") } }
                    Button(role: .destructive) { onDelete() } label: { Label("Unsend", systemImage: "trash") }
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if isLive {
            Label("Live location", systemImage: "dot.radiowaves.left.and.right").bold()
            Text("Tap to follow on map").font(.caption2).bold().foregroundColor(mine ? .white.opacity(0.85) : Brand.tealDeep)
        } else if isPin {
            Label(m.pinName.isEmpty ? "Shared location" : m.pinName, systemImage: "mappin.circle.fill").bold()
            if !m.pinNote.isEmpty { Text(m.pinNote).font(.caption) }
            Text("Tap to view on map").font(.caption2).bold().foregroundColor(mine ? .white.opacity(0.85) : Brand.tealDeep)
        } else if isImage {
            if let img = Img.decode(m.image) {
                Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: 240, maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.2)).frame(width: 200, height: 140)
                    .overlay(Image(systemName: "photo").font(.title).foregroundColor(.secondary))
            }
        } else {
            Text(m.text)
            if m.edited {
                Text("(edited)").font(.caption2).italic()
                    .foregroundColor(mine ? .white.opacity(0.7) : .secondary)
            }
        }
    }
}

func stamp(_ ts: Int64) -> String {
    let f = DateFormatter(); f.dateFormat = "h:mm a"
    return f.string(from: Date(timeIntervalSince1970: Double(ts) / 1000))
}
