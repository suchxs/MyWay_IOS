// MainActivity's LiveShareDialog → SwiftUI. Choose who can see your live location for 1 hour: whole
// groups, all friends, or close friends. Sharing to a group also posts a live card into that group's chat.
import SwiftUI
import FirebaseFirestore

struct ShareLocationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let myUid: String
    let myTag: String
    @ObservedObject private var trip = TripManager.shared

    @State private var groups: [TravelGroup] = []
    @State private var selGroups: Set<String> = []
    @State private var allFriends = false
    @State private var closeFriends = false

    private var active: Bool { trip.sharingLive }
    private var canShare: Bool { !selGroups.isEmpty || allFriends || closeFriends }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header

                        VStack(spacing: 0) {
                            toggleRow("All friends", systemImage: "person.2.fill", on: $allFriends)
                            Divider().padding(.leading, 52)
                            toggleRow("Close friends only", systemImage: "star.fill", on: $closeFriends)
                        }
                        .background(cardBg)

                        if !groups.isEmpty {
                            Text("GROUPS").font(.caption).bold().foregroundColor(.secondary).padding(.leading, 4)
                            VStack(spacing: 0) {
                                ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
                                    groupRow(g)
                                    if i < groups.count - 1 { Divider().padding(.leading, 58) }
                                }
                            }
                            .background(cardBg)
                        }
                    }
                    .padding(16)
                }

                // Fixed action bar
                VStack(spacing: 10) {
                    Button { share() } label: {
                        Label("Share for 1 hour", systemImage: "location.fill").bold().frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Brand.teal).controlSize(.large)
                    .disabled(!canShare)
                    if active {
                        Button("Stop sharing", role: .destructive) { trip.stopLiveShare(); dismiss() }
                    }
                }
                .padding(16)
                .background(.regularMaterial)
            }
            .navigationTitle(active ? "Live location" : "Share location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { Groups.fetchMyGroups(myUid) { groups = $0 } }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack { Circle().fill(Brand.teal.opacity(0.15)); Image(systemName: "dot.radiowaves.left.and.right").foregroundColor(Brand.teal).font(.title3) }
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(active ? "You're sharing live" : "Share live location").font(.headline)
                Text("Anyone you pick can see you for 1 hour.").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var cardBg: some View { RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)) }

    private func toggleRow(_ title: String, systemImage: String, on: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).foregroundColor(Brand.teal).frame(width: 28)
            Text(title)
            Spacer()
            Toggle("", isOn: on).labelsHidden().tint(Brand.teal)
        }.padding(.horizontal, 12).padding(.vertical, 12)
    }

    private func groupRow(_ g: TravelGroup) -> some View {
        Button { toggle(g.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: selGroups.contains(g.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selGroups.contains(g.id) ? Brand.teal : .secondary).font(.title3)
                AvatarCircle(photoBase64: g.photo, tag: g.name, size: 34)
                Text(g.name).foregroundColor(.primary)
                Spacer()
            }.padding(.horizontal, 12).padding(.vertical, 10)
        }.tint(.primary)
    }

    private func toggle(_ gid: String) { if selGroups.contains(gid) { selGroups.remove(gid) } else { selGroups.insert(gid) } }

    // Compute visibleTo (group members + friends) so recipients' maps discover the marker, then start
    // the share and post a live card into each selected group's chat.
    private func share() {
        guard let c = AppState.shared.lastLocation else { dismiss(); return }
        var visible = Set<String>()
        for gid in selGroups { if let g = groups.first(where: { $0.id == gid }) { visible.formUnion(g.members.filter { $0 != myUid }) } }

        let finish = {
            LiveShare.start(uid: myUid, tag: myTag, photo: AppState.shared.userPhoto(myUid),
                            groups: Array(selGroups), allFriends: allFriends, closeFriends: closeFriends,
                            uids: [], visibleTo: Array(visible), lat: c.latitude, lng: c.longitude) { _ in
                for gid in selGroups { Groups.postLiveShare(gid, fromUid: myUid, fromTag: myTag) }
            }
            dismiss()
        }

        if allFriends || closeFriends {
            let group = DispatchGroup()
            if allFriends { group.enter(); Friends.fetchFriendUids(myUid) { visible.formUnion($0); group.leave() } }
            if closeFriends { group.enter(); Friends.fetchCloseFriendUids(myUid) { visible.formUnion($0); group.leave() } }
            group.notify(queue: .main) { finish() }
        } else { finish() }
    }
}
