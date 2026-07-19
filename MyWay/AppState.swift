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

    // Unread counts for the sidebar badge + inbox tabs (App.unreadAllCount/unreadGroupsCount).
    @Published var unreadAllCount = 0      // DMs + groups
    @Published var unreadGroupsCount = 0   // groups only

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
    private var chatsReg: ListenerRegistration?
    private var groupsReg: ListenerRegistration?
    private var rawChats: [PrivateChat] = []
    private var rawGroups: [TravelGroup] = []

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
        // Always-on unread listeners so the sidebar badge + inbox tabs stay live app-wide.
        chatsReg = PrivateMessages.listenMyChats(uid) { [weak self] list in
            Task { @MainActor in self?.rawChats = list; self?.updateUnreadCounts() }
        }
        groupsReg = Groups.listenMyGroups(uid) { [weak self] list in
            Task { @MainActor in self?.rawGroups = list; self?.updateUnreadCounts() }
        }
    }

    private func updateUnreadCounts() {
        let dms = rawChats.filter { $0.isUnread(uid) && !$0.isArchived(uid) }.count
        let grps = rawGroups.filter { $0.isUnread(uid) && !$0.isArchived(uid) }.count
        unreadGroupsCount = grps
        unreadAllCount = dms + grps
    }

    func unbindUser() {
        placesReg?.remove(); collsReg?.remove(); chatsReg?.remove(); groupsReg?.remove()
        placesReg = nil; collsReg = nil; chatsReg = nil; groupsReg = nil; uid = ""
        places = []; collections = []
        rawChats = []; rawGroups = []; unreadAllCount = 0; unreadGroupsCount = 0
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

    /// Import a collection someone shared in chat: save each pin, then a new collection holding them.
    func importSharedCollection(name: String, icon: String, pins: [SharedPin]) {
        for p in pins {
            let key = locationKey(p.lat, p.lng)
            saveLocation(CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng))
            if !p.name.isEmpty { saveName(key, p.name) }
            if !p.note.isEmpty { saveNote(key, p.note) }
        }
        saveCollection(PlaceCollection(name: name.isEmpty ? "Shared collection" : name,
                                       icon: icon.isEmpty ? "🗂️" : icon,
                                       keys: pins.map { locationKey($0.lat, $0.lng) }))
    }

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

    /// Wipe only saved waypoints (App.clearMyPlaces) — collections are left intact.
    func clearMyPlaces() {
        if !uid.isEmpty { Places.deletePlaces(uid) }
        places = []
    }

    /// Wipe only collections (App.clearAllCollections) — saved waypoints are left intact.
    func clearAllCollections() {
        if !uid.isEmpty { Places.deleteCollections(uid) }
        collections = []
    }

    func signOut() {
        unbindUser()
    }
}
