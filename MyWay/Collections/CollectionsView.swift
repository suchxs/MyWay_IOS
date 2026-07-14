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
            Section("All pins (\(state.places.count))") {
                ForEach(state.places) { p in
                    VStack(alignment: .leading) {
                        Text(p.name.isEmpty ? (p.isLandmark ? "Landmark" : "Saved pin") : p.name).bold()
                        if !p.note.isEmpty { Text(p.note).font(.caption).foregroundColor(.secondary) }
                        Text(p.key).font(.caption2).foregroundColor(.secondary)
                    }
                }
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

    private var pins: [SavedPlace] { state.places.filter { collection.locationKeys.contains($0.key) } }

    var body: some View {
        List(pins) { p in
            VStack(alignment: .leading) {
                Text(p.name.isEmpty ? "Saved pin" : p.name).bold()
                if !p.note.isEmpty { Text(p.note).font(.caption).foregroundColor(.secondary) }
            }
        }
        .navigationTitle("\(collection.icon) \(collection.name)")
    }
}
