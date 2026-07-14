// App.kt equivalent: the in-memory mirror of the signed-in user's places + collections, kept live by
// Firestore snapshot listeners, plus device-local settings (dark mode, marker look, @tag/avatar cache)
// which live in UserDefaults instead of Android's SharedPreferences.
import Foundation
import SwiftUI
import FirebaseFirestore
import CoreLocation

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // Live mirror — SwiftUI screens observe these directly (replaces App.dataVersion repaint bumps).
    @Published var places: [SavedPlace] = []
    @Published var collections: [PlaceCollection] = []

    // Last known location so screens can seed without their own GPS fix (App.lastLat/lastLng).
    @Published var lastLocation: CLLocationCoordinate2D?

    // ── Device settings (UserDefaults) ──────────────────────────────────────────
    @Published var darkMode: Bool = UserDefaults.standard.bool(forKey: "dark_mode") {
        didSet { UserDefaults.standard.set(darkMode, forKey: "dark_mode") }
    }
    var pinHue: Double {
        get { UserDefaults.standard.double(forKey: "pin_hue") }
        set { UserDefaults.standard.set(newValue, forKey: "pin_hue") }
    }
    // Marker-appearance settings (App.kt getPinIcon/getPencilIcon).
    var pinIcon: String {
        get { UserDefaults.standard.string(forKey: "pin_icon") ?? "📝" }
        set { UserDefaults.standard.set(newValue, forKey: "pin_icon") }
    }
    var pencilIcon: String {
        get { UserDefaults.standard.string(forKey: "pencil_icon") ?? "✏️" }
        set { UserDefaults.standard.set(newValue, forKey: "pencil_icon") }
    }
    func userTag(_ uid: String) -> String { UserDefaults.standard.string(forKey: "usertag_\(uid)") ?? "" }
    func setUserTag(_ uid: String, _ tag: String) { UserDefaults.standard.set(tag, forKey: "usertag_\(uid)") }
    func userPhoto(_ uid: String) -> String { UserDefaults.standard.string(forKey: "userphoto_\(uid)") ?? "" }
    func setUserPhoto(_ uid: String, _ photo: String) { UserDefaults.standard.set(photo, forKey: "userphoto_\(uid)") }

    private var uid = ""
    private var placesReg: ListenerRegistration?
    private var collsReg: ListenerRegistration?

    // ── Firestore binding (App.bindUser/unbindUser) — idempotent ─────────────────
    func bindUser(_ uid: String) {
        guard !uid.isEmpty, uid != self.uid else { return }
        unbindUser()
        self.uid = uid
        placesReg = Places.listenPlaces(uid) { [weak self] docs in
            Task { @MainActor in self?.places = docs }
        }
        collsReg = Places.listenCollections(uid) { [weak self] colls in
            Task { @MainActor in self?.collections = colls }
        }
    }

    func unbindUser() {
        placesReg?.remove(); collsReg?.remove()
        placesReg = nil; collsReg = nil; uid = ""
        places = []; collections = []
    }

    // ── Places ───────────────────────────────────────────────────────────────────
    func saveLocation(_ coord: CLLocationCoordinate2D) {
        Places.savePlace(uid, key: locationKey(coord.latitude, coord.longitude), lat: coord.latitude, lng: coord.longitude)
    }

    func removeLocation(_ place: SavedPlace) {
        Places.deletePlace(uid, key: place.key)
        for var c in collections where c.locationKeys.contains(place.key) {
            c.locationKeys.removeAll { $0 == place.key }
            Places.saveCollection(uid, c)
        }
    }

    func saveNote(_ key: String, _ note: String) { Places.setPlaceField(uid, key: key, field: "note", value: note) }
    func saveName(_ key: String, _ name: String) { Places.setPlaceField(uid, key: key, field: "name", value: name) }

    // ── Collections ────────────────────────────────────────────────────────────────
    func saveCollection(_ c: PlaceCollection) { Places.saveCollection(uid, c) }
    func removeCollection(_ c: PlaceCollection) { Places.deleteCollection(uid, id: c.id) }

    /// One collection per pin (App.setPinCollection): drop [key] from all, add to [target] (nil = none).
    func setPinCollection(_ key: String, target: PlaceCollection?) {
        for var c in collections where c.id != target?.id && c.locationKeys.contains(key) {
            c.locationKeys.removeAll { $0 == key }
            Places.saveCollection(uid, c)
        }
        if var t = target, !t.locationKeys.contains(key) {
            t.locationKeys.append(key)
            Places.saveCollection(uid, t)
        }
    }

    func clearMyPlaces() {
        if !uid.isEmpty { Places.deleteAll(uid) }
        places = []; collections = []
    }

    func signOut() {
        unbindUser()
    }
}
