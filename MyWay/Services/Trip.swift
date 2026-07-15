// Trip.kt → Swift. Group Trips: a live session tied to a group. One participant doc per user (keyed by
// uid) → single-trip-at-a-time. Live location, shared pins, a shared destination, and a shared plan.
//   trip_participants/{uid}     { uid, gid, tag, photo, lat, lng, updatedAt, expireAt }
//   groups/{gid}/trip_pins/{id} { from, fromTag, fromPhoto, lat, lng, name, note, createdAt }
//   groups/{gid}.tripDest       { id, lat, lng, name, by, byTag, done[], planItemId }
//   groups/{gid}/trip_plan/current, groups/{gid}/trip_offers/{id}
import FirebaseFirestore
import FirebaseCore

struct TripMember: Identifiable, Equatable {
    let uid, tag, photo: String
    let lat, lng: Double?
    var id: String { uid }
}
struct TripPin: Identifiable, Equatable {
    let id, from, fromTag, fromPhoto: String
    let lat, lng: Double
    var name, note: String
}
struct TripDest: Equatable, Identifiable {
    let id: String; let lat, lng: Double
    let name, by, byTag: String
    let done: [String]; var planItemId = ""
}
struct PlanItem: Identifiable, Equatable {
    let id, name: String; let lat, lng: Double; var finished: Bool
}
struct TripPlan: Equatable {
    let name: String; let paused, archived: Bool; let items: [PlanItem]
    var activeItem: PlanItem? { (paused || archived) ? nil : items.first { !$0.finished } }
    var complete: Bool { !items.isEmpty && items.allSatisfy { $0.finished } }
}
struct OfferPin: Equatable { let lat, lng: Double; let name, note: String }
struct TripOffer: Identifiable, Equatable {
    let id, from, fromTag, fromPhoto, name: String; let pins: [OfferPin]
}

enum Trip {
    private static let STALE: TimeInterval = 60
    private static let TTL: TimeInterval = 90
    private static let OFFER_TTL: TimeInterval = 15 * 60

    private static var db: Firestore { Firestore.firestore() }
    private static func meRef(_ uid: String) -> DocumentReference { db.collection("trip_participants").document(uid) }
    private static func expiry() -> Timestamp { Timestamp(date: Date().addingTimeInterval(TTL)) }

    /// Fresh if we've heard from them recently. A just-joined doc (no server ts yet) counts as fresh.
    private static func fresh(_ d: DocumentSnapshot) -> Bool {
        guard let ts = d.get("updatedAt") as? Timestamp else { return true }
        return Date().timeIntervalSince(ts.dateValue()) < STALE
    }

    // ── Participation ────────────────────────────────────────────────────────────
    static func join(_ uid: String, gid: String, tag: String, photo: String, lat: Double, lng: Double, onDone: @escaping (String?) -> Void) {
        var data: [String: Any] = ["uid": uid, "gid": gid, "tag": tag, "photo": photo,
                                   "updatedAt": FieldValue.serverTimestamp(), "expireAt": expiry()]
        if lat != 0 || lng != 0 { data["lat"] = lat; data["lng"] = lng }
        meRef(uid).setData(data) { onDone($0?.localizedDescription) }
    }

    static func leave(_ uid: String, onDone: @escaping (String?) -> Void) {
        meRef(uid).delete { onDone($0?.localizedDescription) }
    }

    /// Update my participant marker's photo (e.g. after changing it mid-trip). No-op if not in a trip.
    static func updatePhoto(_ uid: String, photo: String) { meRef(uid).updateData(["photo": photo]) }

    /// Fire-and-forget live-location update + heartbeat. update() so a left/deleted doc stays gone.
    static func updateLocation(_ uid: String, lat: Double, lng: Double) {
        meRef(uid).updateData(["lat": lat, "lng": lng, "updatedAt": FieldValue.serverTimestamp(), "expireAt": expiry()])
    }

    static func listenMyTrip(_ uid: String, onChange: @escaping (String?) -> Void) -> ListenerRegistration {
        meRef(uid).addSnapshotListener { d, _ in onChange(d?.exists == true ? d?.get("gid") as? String : nil) }
    }

    static func currentTrip(_ uid: String, onResult: @escaping (String?) -> Void) {
        meRef(uid).getDocument { d, _ in onResult(d?.exists == true ? d?.get("gid") as? String : nil) }
    }

    static func listenMembers(_ gid: String, onChange: @escaping ([TripMember]) -> Void) -> ListenerRegistration {
        db.collection("trip_participants").whereField("gid", isEqualTo: gid)
            .addSnapshotListener { snap, _ in
                guard let snap else { return }
                onChange(snap.documents.compactMap { d in
                    guard fresh(d), let uid = d.get("uid") as? String else { return nil }
                    return TripMember(uid: uid, tag: d.get("tag") as? String ?? "", photo: d.get("photo") as? String ?? "",
                                      lat: d.get("lat") as? Double, lng: d.get("lng") as? Double)
                })
            }
    }

    // ── Session ────────────────────────────────────────────────────────────────────
    static func startSession(_ gid: String, onDone: @escaping (String?) -> Void) {
        db.collection("groups").document(gid).updateData(["tripActive": true]) { onDone($0?.localizedDescription) }
    }

    /// End the session (any member): clears participants + pins + offers + plan, marks not-in-trip.
    static func endSession(_ gid: String, onDone: @escaping (String?) -> Void) {
        let groupRef = db.collection("groups").document(gid)
        let pinsCol = groupRef.collection("trip_pins")
        let offersCol = groupRef.collection("trip_offers")
        let partsQ = db.collection("trip_participants").whereField("gid", isEqualTo: gid)
        pinsCol.getDocuments { pinSnap, _ in
            offersCol.getDocuments { offerSnap, _ in
                partsQ.getDocuments { partSnap, _ in
                    let batch = db.batch()
                    pinSnap?.documents.forEach { batch.deleteDocument($0.reference) }
                    offerSnap?.documents.forEach { batch.deleteDocument($0.reference) }
                    partSnap?.documents.forEach { batch.deleteDocument($0.reference) }
                    batch.deleteDocument(planRef(gid))
                    batch.updateData(["tripActive": false, "tripDest": FieldValue.delete()], forDocument: groupRef)
                    batch.commit { onDone($0?.localizedDescription) }
                }
            }
        }
    }

    // ── Shared destination (inline on the group doc) ─────────────────────────────────
    static func setTripDest(_ gid: String, lat: Double, lng: Double, name: String, byUid: String, byTag: String, onDone: @escaping (String?) -> Void) {
        db.collection("groups").document(gid).updateData([
            "tripDest": ["id": String(Int64(Date().timeIntervalSince1970 * 1000)),
                         "lat": lat, "lng": lng, "name": name, "by": byUid, "byTag": byTag, "done": [String]()]
        ]) { onDone($0?.localizedDescription) }
    }

    static func listenTripDest(_ gid: String, onChange: @escaping (TripDest?) -> Void) -> ListenerRegistration {
        db.collection("groups").document(gid).addSnapshotListener { d, _ in
            guard let m = d?.get("tripDest") as? [String: Any],
                  let lat = (m["lat"] as? NSNumber)?.doubleValue, let lng = (m["lng"] as? NSNumber)?.doubleValue else {
                onChange(nil); return
            }
            onChange(TripDest(id: "\(m["id"] ?? "")", lat: lat, lng: lng,
                              name: "\(m["name"] ?? "")", by: "\(m["by"] ?? "")", byTag: "\(m["byTag"] ?? "")",
                              done: (m["done"] as? [String]) ?? [], planItemId: "\(m["planItemId"] ?? "")"))
        }
    }

    static func endTripDestForMe(_ gid: String, uid: String) {
        let groupRef = db.collection("groups").document(gid)
        groupRef.updateData(["tripDest.done": FieldValue.arrayUnion([uid])]) { _ in
            db.collection("trip_participants").whereField("gid", isEqualTo: gid).getDocuments { parts, _ in
                groupRef.getDocument { g, _ in
                    guard let dest = g?.get("tripDest") as? [String: Any] else { return }
                    let done = Set((dest["done"] as? [String]) ?? [])
                    let live = (parts?.documents ?? []).filter { fresh($0) }.compactMap { $0.get("uid") as? String }
                    if !live.isEmpty, live.allSatisfy({ done.contains($0) }) {
                        groupRef.updateData(["tripDest": FieldValue.delete()])
                    }
                }
            }
        }
    }

    // ── Shared pins ──────────────────────────────────────────────────────────────────
    static func sharePin(_ gid: String, fromUid: String, fromTag: String, fromPhoto: String, lat: Double, lng: Double, name: String, note: String) {
        db.collection("groups").document(gid).collection("trip_pins").document().setData([
            "from": fromUid, "fromTag": fromTag, "fromPhoto": fromPhoto, "lat": lat, "lng": lng,
            "name": name, "note": note, "createdAt": FieldValue.serverTimestamp()])
    }

    static func listenPins(_ gid: String, onChange: @escaping ([TripPin]) -> Void) -> ListenerRegistration {
        db.collection("groups").document(gid).collection("trip_pins")
            .addSnapshotListener { snap, _ in
                guard let snap else { return }
                onChange(snap.documents.compactMap { d in
                    guard let lat = d.get("lat") as? Double, let lng = d.get("lng") as? Double else { return nil }
                    return TripPin(id: d.documentID, from: d.get("from") as? String ?? "",
                                   fromTag: d.get("fromTag") as? String ?? "", fromPhoto: d.get("fromPhoto") as? String ?? "",
                                   lat: lat, lng: lng, name: d.get("name") as? String ?? "", note: d.get("note") as? String ?? "")
                })
            }
    }

    static func updatePin(_ gid: String, pinId: String, name: String, note: String, onDone: @escaping (String?) -> Void) {
        db.collection("groups").document(gid).collection("trip_pins").document(pinId)
            .updateData(["name": name, "note": note]) { onDone($0?.localizedDescription) }
    }

    static func deletePin(_ gid: String, pinId: String, onDone: @escaping (String?) -> Void) {
        db.collection("groups").document(gid).collection("trip_pins").document(pinId).delete { onDone($0?.localizedDescription) }
    }

    // ── Plan (shared ordered objectives that steer the group direction) ───────────────
    private static func planRef(_ gid: String) -> DocumentReference {
        db.collection("groups").document(gid).collection("trip_plan").document("current")
    }

    private static func parseItems(_ d: DocumentSnapshot) -> [PlanItem] {
        let raw = (d.get("items") as? [[String: Any]]) ?? []
        return raw.compactMap { m in
            guard let lat = (m["lat"] as? NSNumber)?.doubleValue, let lng = (m["lng"] as? NSNumber)?.doubleValue else { return nil }
            return PlanItem(id: "\(m["id"] ?? "")", name: "\(m["name"] ?? "")", lat: lat, lng: lng, finished: m["finished"] as? Bool ?? false)
        }
    }

    static func listenPlan(_ gid: String, onChange: @escaping (TripPlan?) -> Void) -> ListenerRegistration {
        planRef(gid).addSnapshotListener { d, _ in
            guard let d, d.exists else { onChange(nil); return }
            onChange(TripPlan(name: d.get("name") as? String ?? "Plan", paused: d.get("paused") as? Bool ?? false,
                              archived: d.get("archived") as? Bool ?? false, items: parseItems(d)))
        }
    }

    private final class PlanState { var name: String; var paused: Bool; var items: [PlanItem]
        init(_ n: String, _ p: Bool, _ i: [PlanItem]) { name = n; paused = p; items = i } }

    /// Read the plan, apply [edit], write it back, re-point tripDest at the active item — all in a txn.
    private static func edit(_ gid: String, actorUid: String, actorTag: String, onDone: @escaping (String?) -> Void,
                             _ mutate: @escaping (PlanState?) -> PlanState?) {
        let pRef = planRef(gid); let gRef = db.collection("groups").document(gid)
        db.runTransaction({ txn, _ -> Any? in
            let snap = try? txn.getDocument(pRef)
            let cur: PlanState? = (snap?.exists == true)
                ? PlanState(snap?.get("name") as? String ?? "Plan", snap?.get("paused") as? Bool ?? false, parseItems(snap!))
                : nil
            guard let next = mutate(cur) else { return nil }
            let archived = !next.items.isEmpty && next.items.allSatisfy { $0.finished }
            txn.setData(["name": next.name, "paused": next.paused, "archived": archived,
                         "items": next.items.map { ["id": $0.id, "name": $0.name, "lat": $0.lat, "lng": $0.lng, "finished": $0.finished] }],
                        forDocument: pRef)
            if !next.paused {
                let active = archived ? nil : next.items.first { !$0.finished }
                if let active {
                    txn.updateData(["tripDest": ["id": active.id, "lat": active.lat, "lng": active.lng, "name": active.name,
                                                 "by": actorUid, "byTag": actorTag, "done": [String](), "planItemId": active.id]], forDocument: gRef)
                } else {
                    txn.updateData(["tripDest": FieldValue.delete()], forDocument: gRef)
                }
            }
            return nil
        }) { _, err in onDone(err?.localizedDescription) }
    }

    private static func newId() -> String { String(UUID().uuidString.prefix(10)) }

    static func createPlan(_ gid: String, name: String, actorUid: String, actorTag: String, onDone: @escaping (String?) -> Void) {
        edit(gid, actorUid: actorUid, actorTag: actorTag, onDone: onDone) { _ in PlanState(name.isEmpty ? "Trip plan" : name, false, []) }
    }

    static func addPlanItem(_ gid: String, name: String, lat: Double, lng: Double, actorUid: String, actorTag: String, onDone: @escaping (String?) -> Void) {
        edit(gid, actorUid: actorUid, actorTag: actorTag, onDone: onDone) { cur in
            guard let cur else { return nil }
            cur.items.append(PlanItem(id: newId(), name: name, lat: lat, lng: lng, finished: false)); return cur
        }
    }

    static func prependPlanItem(_ gid: String, name: String, lat: Double, lng: Double, actorUid: String, actorTag: String, onDone: @escaping (String?) -> Void) {
        edit(gid, actorUid: actorUid, actorTag: actorTag, onDone: onDone) { cur in
            guard let cur else { return nil }
            cur.items.insert(PlanItem(id: newId(), name: name, lat: lat, lng: lng, finished: false), at: 0); return cur
        }
    }

    static func setItemFinished(_ gid: String, itemId: String, finished: Bool, actorUid: String, actorTag: String, onDone: @escaping (String?) -> Void) {
        edit(gid, actorUid: actorUid, actorTag: actorTag, onDone: onDone) { cur in
            guard let cur else { return nil }
            if let i = cur.items.firstIndex(where: { $0.id == itemId }) { cur.items[i].finished = finished }
            return cur
        }
    }

    static func setPlanPaused(_ gid: String, paused: Bool, actorUid: String, actorTag: String, onDone: @escaping (String?) -> Void) {
        edit(gid, actorUid: actorUid, actorTag: actorTag, onDone: onDone) { cur in guard let cur else { return nil }; cur.paused = paused; return cur }
    }
}
