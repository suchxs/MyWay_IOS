// Bridges imperative GMSMapView state back to SwiftUI: the live map bearing (for the compass button)
// and a weak handle so the compass can reset north.
import GoogleMaps

@MainActor
final class MapHolder: ObservableObject {
    weak var map: GMSMapView?
    @Published var bearing: Double = 0
    @Published var cameraTick = 0        // bumped on every camera change so overlays (trip arrows) recompute
    func resetNorth() { map?.animate(toBearing: 0) }

    /// Frame the whole route in view (Google Maps' route overview before you press Start).
    func fit(_ coords: [CLLocationCoordinate2D], padding: CGFloat = 90) {
        guard coords.count > 1, let map else { return }
        var bounds = GMSCoordinateBounds()
        for c in coords { bounds = bounds.includingCoordinate(c) }
        map.animate(with: GMSCameraUpdate.fit(bounds, with: UIEdgeInsets(top: padding + 40, left: padding, bottom: padding + 160, right: padding)))
    }
}
