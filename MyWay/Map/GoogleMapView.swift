// GMSMapView wrapped for SwiftUI (Android used maps-compose GoogleMap + MapMarkerManager).
// Renders the user's saved places, plus — during a trip — live members, shared trip pins, and the
// shared destination. Tap a saved marker to select it, long-press to drop a new one.
import SwiftUI
import GoogleMaps

struct GoogleMapView: UIViewRepresentable {
    var places: [SavedPlace]
    var pinHue: Double
    var dark: Bool
    var members: [TripMember] = []
    var tripPins: [TripPin] = []
    var dest: TripDest? = nil
    var myUid: String = ""
    @Binding var camera: GMSCameraPosition?
    var onTapMarker: (SavedPlace) -> Void
    var onLongPress: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> GMSMapView {
        let view = GMSMapView()
        view.delegate = context.coordinator
        view.isMyLocationEnabled = true
        view.settings.myLocationButton = true
        applyStyle(view)
        return view
    }

    func updateUIView(_ view: GMSMapView, context: Context) {
        applyStyle(view)
        if let camera { view.animate(to: camera) }
        // Rebuild markers only when something changed (cheap for a personal map + a handful of trip pins).
        let placeSig = places.map(\.key).joined()
        let memberSig = members.map { "\($0.uid)\($0.lat ?? 0)\($0.lng ?? 0)" }.joined()
        let pinSig = tripPins.map(\.id).joined()
        let destSig = dest.map { "\($0.lat)\($0.lng)" } ?? ""
        let signature = "\(placeSig)|\(pinHue)|\(memberSig)|\(pinSig)|\(destSig)"
        guard context.coordinator.lastSignature != signature else { return }
        context.coordinator.lastSignature = signature
        view.clear()

        for place in places {
            let marker = GMSMarker(position: place.coordinate)
            marker.icon = GMSMarker.markerImage(with: UIColor(hue: CGFloat(pinHue / 360.0), saturation: 0.75, brightness: 0.9, alpha: 1))
            marker.title = place.name.isEmpty ? (place.isLandmark ? "Landmark" : "Saved pin") : place.name
            marker.snippet = place.note
            marker.userData = place.key
            marker.map = view
        }
        // Trip members (blue), skipping myself; trip pins (violet); shared destination (green).
        for m in members where m.uid != myUid {
            guard let lat = m.lat, let lng = m.lng else { continue }
            let marker = GMSMarker(position: CLLocationCoordinate2D(latitude: lat, longitude: lng))
            marker.icon = GMSMarker.markerImage(with: .systemBlue)
            marker.title = "@\(m.tag)"
            marker.map = view
        }
        for p in tripPins {
            let marker = GMSMarker(position: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng))
            marker.icon = GMSMarker.markerImage(with: .systemPurple)
            marker.title = p.name.isEmpty ? "Trip pin" : p.name
            marker.snippet = "@\(p.fromTag)"
            marker.map = view
        }
        if let dest {
            let marker = GMSMarker(position: CLLocationCoordinate2D(latitude: dest.lat, longitude: dest.lng))
            marker.icon = GMSMarker.markerImage(with: .systemGreen)
            marker.title = dest.name.isEmpty ? "Destination" : dest.name
            marker.map = view
        }
    }

    private func applyStyle(_ view: GMSMapView) {
        view.mapStyle = dark ? try? GMSMapStyle(jsonString: MapStyle.darkJSON) : nil
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        let parent: GoogleMapView
        var lastSignature = ""
        init(_ parent: GoogleMapView) { self.parent = parent }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            if let key = marker.userData as? String, let place = parent.places.first(where: { $0.key == key }) {
                parent.onTapMarker(place)
                return true
            }
            return false
        }

        func mapView(_ mapView: GMSMapView, didLongPressAt coordinate: CLLocationCoordinate2D) {
            parent.onLongPress(coordinate)
        }
    }
}
