// iOS replacement for TripLocationService.kt. Android used a foreground Service; iOS uses a background
// CLLocationManager (UIBackgroundModes: location) driven by the same "watch my participant doc" logic.
// Single source of truth: publishing runs exactly while trip_participants/{uid} exists.
import Foundation
import CoreLocation
import FirebaseFirestore

@MainActor
final class TripManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = TripManager()

    @Published var currentGid: String?          // my active trip's group id (nil = not in a trip)
    @Published var groupName = ""
    @Published var members: [TripMember] = []
    @Published var pins: [TripPin] = []
    @Published var dest: TripDest?
    @Published var sharingLive = false          // a LiveShare is active

    private var uid = ""
    private var myTag = ""
    private var myPhoto = ""
    private let manager = CLLocationManager()
    private var lastWrite = Date.distantPast
    private var heartbeat: Timer?

    private var myTripReg: ListenerRegistration?
    private var membersReg: ListenerRegistration?
    private var pinsReg: ListenerRegistration?
    private var destReg: ListenerRegistration?
    private var liveReg: ListenerRegistration?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 15
        manager.pausesLocationUpdatesAutomatically = false
    }

    /// Attach the "which trip am I in" listener. Call on sign-in.
    func bind(uid: String, tag: String, photo: String) {
        guard uid != self.uid else { self.myTag = tag; self.myPhoto = photo; return }
        unbind()
        self.uid = uid; self.myTag = tag; self.myPhoto = photo
        myTripReg = Trip.listenMyTrip(uid) { [weak self] gid in
            Task { @MainActor in self?.onTripChanged(gid) }
        }
        liveReg = LiveShare.listen(uid) { [weak self] state in
            Task { @MainActor in self?.sharingLive = state?.active ?? false }
        }
    }

    func unbind() {
        myTripReg?.remove(); liveReg?.remove()
        detachTripListeners(); stopPublishing()
        uid = ""; currentGid = nil; members = []; pins = []; dest = nil; sharingLive = false
    }

    // ── Actions the UI calls ──────────────────────────────────────────────────────
    /// Join (or start + join) a group's trip. Publishing auto-starts once the participant doc lands.
    func joinTrip(gid: String, groupName: String, tripActive: Bool) {
        let c = AppState.shared.lastLocation
        if !tripActive { Trip.startSession(gid) { _ in } }
        Trip.join(uid, gid: gid, tag: myTag, photo: myPhoto, lat: c?.latitude ?? 0, lng: c?.longitude ?? 0) { [weak self] err in
            if err == nil { Groups.postSystem(gid, text: "@\(self?.myTag ?? "") joined the trip") }
        }
    }

    func leaveTrip() {
        guard !uid.isEmpty else { return }
        let gid = currentGid
        Trip.leave(uid) { _ in if let gid { Groups.postSystem(gid, text: "@\(self.myTag) left the trip") } }
    }

    func endTrip() { if let gid = currentGid { Trip.endSession(gid) { _ in } } }

    func dropPin(name: String, note: String) {
        guard let gid = currentGid, let c = AppState.shared.lastLocation else { return }
        Trip.sharePin(gid, fromUid: uid, fromTag: myTag, fromPhoto: myPhoto, lat: c.latitude, lng: c.longitude, name: name, note: note)
    }

    // ── Trip lifecycle ─────────────────────────────────────────────────────────────
    private func onTripChanged(_ gid: String?) {
        currentGid = gid
        detachTripListeners()
        guard let gid else { stopPublishing(); members = []; pins = []; dest = nil; return }

        Groups.fetchNamePhoto(gid) { [weak self] name, _ in Task { @MainActor in self?.groupName = name } }
        membersReg = Trip.listenMembers(gid) { [weak self] m in Task { @MainActor in self?.members = m } }
        pinsReg = Trip.listenPins(gid) { [weak self] p in Task { @MainActor in self?.pins = p } }
        destReg = Trip.listenTripDest(gid) { [weak self] d in Task { @MainActor in self?.dest = d } }
        startPublishing()
    }

    private func detachTripListeners() {
        membersReg?.remove(); pinsReg?.remove(); destReg?.remove()
        membersReg = nil; pinsReg = nil; destReg = nil
    }

    // ── Background location publishing ───────────────────────────────────────────────
    private func startPublishing() {
        manager.requestAlwaysAuthorization()
        if manager.authorizationStatus != .denied {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            manager.startUpdatingLocation()
        }
        heartbeat?.invalidate()
        // Re-write updatedAt/expireAt even when stationary so we don't look stale (20s, matches Android).
        heartbeat = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let gid = self.currentGid, !self.uid.isEmpty, let c = AppState.shared.lastLocation else { return }
                _ = gid
                Trip.updateLocation(self.uid, lat: c.latitude, lng: c.longitude)
                if self.sharingLive { LiveShare.updateLocation(self.uid, lat: c.latitude, lng: c.longitude) }
            }
        }
    }

    private func stopPublishing() {
        heartbeat?.invalidate(); heartbeat = nil
        manager.allowsBackgroundLocationUpdates = false
        if !sharingLive { manager.stopUpdatingLocation() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            AppState.shared.lastLocation = loc.coordinate
            guard self.currentGid != nil || self.sharingLive else { return }
            if Date().timeIntervalSince(self.lastWrite) < 8 { return }   // throttle writes (Android: 8s)
            self.lastWrite = Date()
            if self.currentGid != nil { Trip.updateLocation(self.uid, lat: loc.coordinate.latitude, lng: loc.coordinate.longitude) }
            if self.sharingLive { LiveShare.updateLocation(self.uid, lat: loc.coordinate.latitude, lng: loc.coordinate.longitude) }
        }
    }
}
