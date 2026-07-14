// MessagesActivity + PrivateChatActivity → SwiftUI. DM inbox + 1-on-1 chat. Start a new chat from
// the friends list; open existing ones from the inbox.
import SwiftUI
import PhotosUI
import FirebaseFirestore

struct MessagesView: View {
    let myUid: String
    let myTag: String
    @State private var chats: [PrivateChat] = []
    @State private var showNew = false
    @State private var reg: ListenerRegistration?

    var body: some View {
        List(chats) { chat in
            NavigationLink {
                PrivateChatView(chatId: chat.id, myUid: myUid, myTag: myTag,
                                otherUid: chat.otherUid(myUid), otherTag: chat.otherTag(myUid))
            } label: {
                HStack {
                    AvatarCircle(photoBase64: "", tag: chat.otherTag(myUid), size: 44)
                    VStack(alignment: .leading) {
                        Text("@\(chat.otherTag(myUid))").bold()
                        Text(chat.lastMsg).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .navigationTitle("Messages")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { showNew = true } label: { Image(systemName: "square.and.pencil") } } }
        .sheet(isPresented: $showNew) { NewMessageSheet(myUid: myUid, myTag: myTag) }
        .onAppear { reg = PrivateMessages.listenMyChats(myUid) { chats = $0 } }
        .onDisappear { reg?.remove() }
    }
}

/// Pick a friend → open the DM (all inside one NavigationStack, so no iOS-17 APIs needed).
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
                    PrivateChatView(chatId: PrivateMessages.pairId(myUid, f.uid), myUid: myUid, myTag: myTag,
                                    otherUid: f.uid, otherTag: f.tag)
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
    @State private var draft = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var reg: ListenerRegistration?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { m in ChatBubble(message: m, mine: m.from == myUid) }
                    }.padding(12)
                }
                .onChange(of: messages.count) { _ in if let l = messages.last { withAnimation { proxy.scrollTo(l.id, anchor: .bottom) } } }
            }
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
        .onAppear { reg = PrivateMessages.listenMessages(chatId) { messages = $0 } }
        .onDisappear { reg?.remove() }
        .onChange(of: photoItem) { item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
                PrivateMessages.sendImage(chatId, fromUid: myUid, fromTag: myTag, otherUid: otherUid, otherTag: otherTag,
                                          base64: Img.encode(img, maxDimension: 1024, quality: 0.6))
            }
        }
    }
}

/// Shared chat bubble (text or image) used by DMs.
struct ChatBubble: View {
    let message: GroupMessage
    let mine: Bool
    var body: some View {
        HStack {
            if mine { Spacer() }
            Group {
                if let img = Img.decode(message.image) {
                    Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: 220).clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    Text(message.text).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(mine ? Brand.teal : Color.gray.opacity(0.18))
                        .foregroundColor(mine ? .white : .primary).clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            if !mine { Spacer() }
        }
    }
}
