// Places.kt — personal map data, private per user.
//   users/{uid}/places/{key}       { lat, lng, name, note, placeId }
//   users/{uid}/collections/{cid}  { name, icon, keys[] }
import FirebaseFirestore

enum Places {
    private static var db: Firestore { Firestore.firestore() }
    private static func places(_ uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("places")
    }
    private static func colls(_ uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("collections")
    }

    static func listenPlaces(_ uid: String, onChange: @escaping ([SavedPlace]) -> Void) -> ListenerRegistration {
        places(uid).addSnapshotListener { snap, _ in
            guard let snap else { return }
            onChange(snap.documents.compactMap { d in
                guard let lat = d.get("lat") as? Double, let lng = d.get("lng") as? Double else { return nil }
                return SavedPlace(key: d.documentID, lat: lat, lng: lng,
                                  name: d.get("name") as? String ?? "",
                                  note: d.get("note") as? String ?? "",
                                  placeId: d.get("placeId") as? String ?? "")
            })
        }
    }

    static func listenCollections(_ uid: String, onChange: @escaping ([PlaceCollection]) -> Void) -> ListenerRegistration {
        colls(uid).addSnapshotListener { snap, _ in
            guard let snap else { return }
            onChange(snap.documents.map { d in
                PlaceCollection(name: d.get("name") as? String ?? "Collection",
                                icon: d.get("icon") as? String ?? "folder",
                                id: d.documentID,
                                keys: d.get("keys") as? [String] ?? [])
            })
        }
    }

    static func savePlace(_ uid: String, key: String, lat: Double, lng: Double) {
        places(uid).document(key).setData(["lat": lat, "lng": lng], merge: true)
    }

    /// Merge one attribute; empty value clears the field.
    static func setPlaceField(_ uid: String, key: String, field: String, value: String) {
        places(uid).document(key).setData([field: value.isEmpty ? FieldValue.delete() : value], merge: true)
    }

    static func deletePlace(_ uid: String, key: String) { places(uid).document(key).delete() }

    static func saveCollection(_ uid: String, _ c: PlaceCollection) {
        colls(uid).document(c.id).setData(["name": c.name, "icon": c.icon, "keys": c.locationKeys])
    }

    static func deleteCollection(_ uid: String, id: String) { colls(uid).document(id).delete() }

    static func deleteAll(_ uid: String) {
        for ref in [places(uid), colls(uid)] {
            ref.getDocuments { snap, _ in
                guard let snap, !snap.isEmpty else { return }
                let batch = db.batch()
                snap.documents.forEach { batch.deleteDocument($0.reference) }
                batch.commit()
            }
        }
    }
}
