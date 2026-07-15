// Plain data models — 1:1 with the Kotlin data classes (Collection.kt, Friends.kt, Groups.kt, Places.kt).
import Foundation
import CoreLocation

// users/{uid}/collections/{id} { name, icon, keys[] }
struct PlaceCollection: Identifiable, Equatable {
    let id: String
    var name: String
    var icon: String
    var locationKeys: [String]

    init(name: String, icon: String, id: String = UUID().uuidString, keys: [String] = []) {
        self.id = id; self.name = name; self.icon = icon; self.locationKeys = keys
    }
}

// users/{uid}/places/{key} { lat, lng, name, note, placeId }
struct SavedPlace: Identifiable, Equatable {
    var id: String { key }               // key = "lat,lng" (Places.locationKey)
    let key: String
    let lat: Double
    let lng: Double
    var name: String = ""
    var note: String = ""
    var placeId: String = ""             // non-empty ⇒ a Google landmark (POI)
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lng) }
    var isLandmark: Bool { !placeId.isEmpty }
}

struct UserHit: Identifiable, Equatable {
    let uid: String
    let tag: String
    var firstName: String = ""
    var lastName: String = ""
    var photo: String = ""
    var isClose: Bool = false
    var id: String { uid }
    var fullName: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }
}

struct FriendRequest: Identifiable, Equatable {
    let id: String
    let fromUid: String
    let fromTag: String
    let toUid: String
    let toTag: String
}

struct Profile {
    var tag: String = ""
    var firstName: String = ""
    var lastName: String = ""
    var photo: String = ""
}

struct TravelGroup: Identifiable, Equatable {
    let id: String
    var name: String
    var owner: String
    var members: [String]
    var admins: [String]
    var tags: [String: String]
    var photo: String = ""
    var tripActive: Bool = false
    var reads: [String: Int64] = [:]
    var lastMsg: String = ""
    var lastTs: Int64 = 0

    func isAdmin(_ uid: String) -> Bool { uid == owner || admins.contains(uid) }
    func tagOf(_ uid: String) -> String { tags[uid] ?? "unknown" }
}

struct GroupMessage: Identifiable, Equatable {
    let id: String
    let from: String
    let fromTag: String
    var text: String = ""
    var image: String = ""
    var pinLat: Double? = nil
    var pinLng: Double? = nil
    var pinName: String = ""
    var pinNote: String = ""
    var pinPlaceId: String = ""
    var system: Bool = false
    var liveFrom: String = ""
    var edited: Bool = false
    var unsent: Bool = false
    // Shared collection card: a whole collection's pins sent into a chat.
    var collName: String = ""
    var collIcon: String = ""
    var collPins: [SharedPin] = []
    var ts: Int64 = 0
}

struct SharedPin: Equatable {
    var lat, lng: Double; var name = ""; var note = ""
    var dict: [String: Any] { ["lat": lat, "lng": lng, "name": name, "note": note] }
}

func parseSharedPins(_ raw: Any?) -> [SharedPin] {
    guard let arr = raw as? [[String: Any]] else { return [] }
    return arr.map { SharedPin(lat: ($0["lat"] as? NSNumber)?.doubleValue ?? 0,
                               lng: ($0["lng"] as? NSNumber)?.doubleValue ?? 0,
                               name: $0["name"] as? String ?? "", note: $0["note"] as? String ?? "") }
}

// Firestore doc id for a place — must match Android's App.locationKey exactly.
func locationKey(_ lat: Double, _ lng: Double) -> String {
    String(format: "%.6f,%.6f", lat, lng)
}
