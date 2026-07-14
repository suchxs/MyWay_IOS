// SearchBar.kt → SwiftUI. Custom place-autocomplete search: each result shows the place name AND its
// address (secondary text) so you can tell similarly-named places apart. Picks hand back id/name/coord.
import SwiftUI
import GooglePlaces
import CoreLocation

struct PlaceSearchView: View {
    @Environment(\.dismiss) private var dismiss
    var onPick: (String, String, CLLocationCoordinate2D) -> Void

    @State private var query = ""
    @State private var predictions: [GMSAutocompletePrediction] = []
    @State private var token = GMSAutocompleteSessionToken()

    var body: some View {
        NavigationStack {
            List(predictions, id: \.placeID) { p in
                Button { pick(p) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill").foregroundColor(Brand.teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.attributedPrimaryText.string).fontWeight(.semibold).foregroundColor(.primary)
                            if let sec = p.attributedSecondaryText?.string, !sec.isEmpty {
                                Text(sec).font(.caption).foregroundColor(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search location…")
            .onChange(of: query) { q in search(q) }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func search(_ q: String) {
        let s = q.trimmingCharacters(in: .whitespaces)
        guard s.count >= 2 else { predictions = []; return }
        GMSPlacesClient.shared().findAutocompletePredictions(fromQuery: s, filter: GMSAutocompleteFilter(), sessionToken: token) { results, _ in
            predictions = results ?? []
        }
    }

    private func pick(_ p: GMSAutocompletePrediction) {
        let name = p.attributedPrimaryText.string
        GMSPlacesClient.shared().fetchPlace(fromPlaceID: p.placeID, placeFields: [.coordinate, .name], sessionToken: token) { place, _ in
            onPick(p.placeID, name, place?.coordinate ?? CLLocationCoordinate2D())
            token = GMSAutocompleteSessionToken()   // end session; fresh token next search
            dismiss()
        }
    }
}
