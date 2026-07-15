// CollectionsActivity.kt → SwiftUI. Browse collections + their pins; create/rename/delete a collection.
import SwiftUI

struct CollectionsView: View {
    @EnvironmentObject var state: AppState
    @State private var showCreate = false
    @State private var newName = ""
    @State private var newIcon = "📁"

    var body: some View {
        List {
            Section("Collections") {
                ForEach(state.collections) { c in
                    NavigationLink { CollectionDetail(collection: c) } label: {
                        HStack {
                            Text(c.icon).font(.title2)
                            Text(c.name)
                            Spacer()
                            Text("\(c.locationKeys.count)").foregroundColor(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { state.removeCollection(c) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            if state.collections.isEmpty {
                Section { Text("No collections yet. Tap + to group your waypoints into a collection.").foregroundColor(.secondary) }
            }
        }
        .navigationTitle("Collections")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { showCreate = true } label: { Image(systemName: "plus") } } }
        .alert("New collection", isPresented: $showCreate) {
            TextField("Emoji", text: $newIcon)
            TextField("Name", text: $newName)
            Button("Create") {
                guard !newName.trimmed.isEmpty else { return }
                state.saveCollection(PlaceCollection(name: newName.trimmed, icon: newIcon.isEmpty ? "📁" : newIcon))
                newName = ""; newIcon = "📁"
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct CollectionDetail: View {
    @EnvironmentObject var state: AppState
    let collection: PlaceCollection
    @State private var showShare = false

    private var pins: [SavedPlace] { state.places.filter { collection.locationKeys.contains($0.key) } }
    private var sharedPins: [SharedPin] { pins.map { SharedPin(lat: $0.lat, lng: $0.lng, name: $0.name, note: $0.note) } }

    var body: some View {
        List(pins) { p in
            VStack(alignment: .leading) {
                Text(p.name.isEmpty ? "Saved pin" : p.name).bold()
                if !p.note.isEmpty { Text(p.note).font(.caption).foregroundColor(.secondary) }
            }
        }
        .navigationTitle("\(collection.icon) \(collection.name)")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showShare = true } label: { Image(systemName: "square.and.arrow.up") }.disabled(pins.isEmpty)
            }
        }
        .sheet(isPresented: $showShare) {
            let myUid = AuthService.currentUid ?? ""
            ShareCollectionSheet(name: collection.name, icon: collection.icon, pins: sharedPins,
                                 myUid: myUid, myTag: state.userTag(myUid))
        }
    }
}
