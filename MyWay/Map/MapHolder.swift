// Bridges imperative GMSMapView state back to SwiftUI: the live map bearing (for the compass button)
// and a weak handle so the compass can reset north. Also owns heading-up ("gyro") mode, which rotates
// the map to the device's facing via the compass — mirrors MainActivity.applyHeadingMode/handleAzimuth.
import GoogleMaps
import CoreLocation

@MainActor
final class MapHolder: NSObject, ObservableObject, CLLocationManagerDelegate {
    weak var map: GMSMapView?
    @Published var bearing: Double = 0
    @Published var cameraTick = 0        // bumped on every camera change so overlays (trip arrows) recompute
    @Published var headingMode = false

    private let compass = CLLocationManager()
    private var smoothedAz = Double.nan
    private var lastApplied = Double.nan

    override init() { super.init(); compass.delegate = self }

    func resetNorth() { map?.animate(toBearing: 0) }

    /// Toggle heading-up mode. On → follow the device compass; off → leave the map where it is.
    func setHeading(_ on: Bool) {
        guard on != headingMode else { return }
        headingMode = on
        if on {
            smoothedAz = .nan; lastApplied = .nan
            compass.startUpdatingHeading()
        } else {
            compass.stopUpdatingHeading()
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateHeading h: CLHeading) {
        let raw = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
        Task { @MainActor in self.applyAzimuth(raw) }
    }

    // Low-pass + threshold the compass azimuth, then rotate the map so facing = screen-up.
    private func applyAzimuth(_ raw: Double) {
        guard headingMode else { return }
        if smoothedAz.isNaN { smoothedAz = raw }
        else {
            var d = raw - smoothedAz
            if d > 180 { d -= 360 } else if d < -180 { d += 360 }
            var v = smoothedAz + d * 0.2
            if v < 0 { v += 360 } else if v >= 360 { v -= 360 }
            smoothedAz = v
        }
        if !lastApplied.isNaN {
            var dd = smoothedAz - lastApplied
            if dd > 180 { dd -= 360 } else if dd < -180 { dd += 360 }
            if abs(dd) < 1.5 { return }
        }
        lastApplied = smoothedAz
        map?.animate(toBearing: smoothedAz)
    }

    /// Frame the whole route in view (Google Maps' route overview before you press Start).
    func fit(_ coords: [CLLocationCoordinate2D], padding: CGFloat = 90) {
        guard coords.count > 1, let map else { return }
        var bounds = GMSCoordinateBounds()
        for c in coords { bounds = bounds.includingCoordinate(c) }
        map.animate(with: GMSCameraUpdate.fit(bounds, with: UIEdgeInsets(top: padding + 40, left: padding, bottom: padding + 160, right: padding)))
    }
}
