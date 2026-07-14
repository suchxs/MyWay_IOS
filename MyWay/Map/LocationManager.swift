// GPS + reverse-geocoding for the map home (Android used FusedLocationProvider + Geocoder).
import CoreLocation
import Combine

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var address = "Waiting for location…"
    @Published var authorized = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastGeocode: CLLocationCoordinate2D?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() { manager.stopUpdatingLocation() }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.location = loc
            AppState.shared.lastLocation = loc.coordinate
            self.reverseGeocode(loc)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let ok = manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
        Task { @MainActor in self.authorized = ok }
    }

    // Only re-geocode when we've moved a meaningful distance (matches Android's throttling).
    private func reverseGeocode(_ loc: CLLocation) {
        if let last = lastGeocode, CLLocation(latitude: last.latitude, longitude: last.longitude).distance(from: loc) < 30 { return }
        lastGeocode = loc.coordinate
        geocoder.reverseGeocodeLocation(loc) { [weak self] marks, _ in
            guard let p = marks?.first else { return }
            let parts = [p.name, p.locality, p.administrativeArea].compactMap { $0 }
            Task { @MainActor in self?.address = parts.isEmpty ? "Unknown location" : parts.joined(separator: ", ") }
        }
    }
}
