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
    @StateObject private var speech = SpeechRecognizer()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search field + mic (SearchBar.kt's voice search).
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search location…", text: $query)
                    if !query.isEmpty {
                        Button { query = ""; predictions = [] } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                    }
                    Button { speech.toggle() } label: {
                        Image(systemName: speech.recording ? "mic.fill" : "mic")
                            .foregroundColor(speech.recording ? Color(hex: 0xEF4444) : Brand.teal)
                    }
                }
                .padding(12).background(Color.gray.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 12).padding(.top, 8)

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
                }.listStyle(.plain)
            }
            .onChange(of: query) { q in search(q) }
            .onChange(of: speech.transcript) { t in if !t.isEmpty { query = t } }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss(); speech.stop() } } }
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
        let props: [GMSPlaceProperty] = [.coordinate, .name]
        let request = GMSFetchPlaceRequest(placeID: p.placeID, placeProperties: props.map(\.rawValue), sessionToken: token)
        GMSPlacesClient.shared().fetchPlace(with: request) { place, _ in
            onPick(p.placeID, name, place?.coordinate ?? CLLocationCoordinate2D())
            token = GMSAutocompleteSessionToken()   // end session; fresh token next search
            dismiss()
        }
    }
}
