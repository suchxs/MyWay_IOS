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
    var scheduledTrip: ScheduledTrip? = nil   // set = a future trip is booked but not yet live

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

// A trip booked for a future time, stored on groups/{gid}.scheduledTrip. `items` become the trip plan
// when it starts. Parsed by Groups.mapGroup; created/cancelled/promoted by Trip.
struct ScheduledTrip: Equatable {
    let name: String
    let startAt: Date
    let by, byTag: String
    let items: [ScheduledStop]

    var dict: [String: Any] {
        ["name": name, "startAt": startAt.timeIntervalSince1970 * 1000, "by": by, "byTag": byTag,
         "items": items.map(\.dict)]
    }
    static func from(_ raw: Any?) -> ScheduledTrip? {
        guard let m = raw as? [String: Any], let ms = (m["startAt"] as? NSNumber)?.doubleValue else { return nil }
        return ScheduledTrip(name: m["name"] as? String ?? "Trip",
                             startAt: Date(timeIntervalSince1970: ms / 1000),
                             by: m["by"] as? String ?? "", byTag: m["byTag"] as? String ?? "",
                             items: (m["items"] as? [[String: Any]] ?? []).map(ScheduledStop.from))
    }
}
struct ScheduledStop: Equatable {
    let id, name: String; let lat, lng: Double
    var dict: [String: Any] { ["id": id, "name": name, "lat": lat, "lng": lng] }
    static func from(_ m: [String: Any]) -> ScheduledStop {
        ScheduledStop(id: "\(m["id"] ?? UUID().uuidString.prefix(10))", name: m["name"] as? String ?? "",
                      lat: (m["lat"] as? NSNumber)?.doubleValue ?? 0, lng: (m["lng"] as? NSNumber)?.doubleValue ?? 0)
    }
}

// Firestore doc id for a place — must match Android's App.locationKey exactly.
func locationKey(_ lat: Double, _ lng: Double) -> String {
    String(format: "%.6f,%.6f", lat, lng)
}
