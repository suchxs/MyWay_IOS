// Directions.kt → Swift. Routes API (New) client: routes + alternatives between two points, each with
// polyline, distance, ETA, and turn-by-turn steps. Plain URLSession + JSONSerialization (no deps).
// Needs "Routes API" enabled and a key WITHOUT an iOS-app restriction (see SETUP.md).
import CoreLocation
import Foundation

enum TravelMode: String, CaseIterable, Identifiable {
    case drive = "DRIVE", walk = "WALK", bicycle = "BICYCLE", transit = "TRANSIT"
    var id: String { rawValue }
    var label: String { ["DRIVE": "Drive", "WALK": "Walk", "BICYCLE": "Bike", "TRANSIT": "Transit"][rawValue] ?? rawValue }
    var systemImage: String { ["DRIVE": "car.fill", "WALK": "figure.walk", "BICYCLE": "bicycle", "TRANSIT": "bus.fill"][rawValue] ?? "car.fill" }
}

struct RouteStep: Equatable {
    let instruction: String
    let maneuver: String
    let distanceMeters: Int
    let endLat, endLng: Double
}

struct RouteResult: Identifiable, Equatable {
    let id = UUID()
    let points: [CLLocationCoordinate2D]
    let distanceMeters: Int
    let durationSeconds: Int
    let steps: [RouteStep]

    static func == (a: RouteResult, b: RouteResult) -> Bool { a.id == b.id }
}

struct RouteFetch { let routes: [RouteResult]; let error: String? }

enum Directions {
    /// All routes (route 0 = recommended). `error` is non-nil when the request itself failed (e.g. the
    /// Routes API isn't enabled, or the key is iOS-app-restricted so REST calls are rejected).
    static func fetchRoute(origin: CLLocationCoordinate2D, dest: CLLocationCoordinate2D, mode: TravelMode) async -> RouteFetch {
        guard let url = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes") else {
            return RouteFetch(routes: [], error: "Bad URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(MapsConfig.routesKey, forHTTPHeaderField: "X-Goog-Api-Key")
        // Lets an iOS-app-restricted key authorize this REST call (otherwise Google sees "<empty>" bundle).
        req.setValue(Bundle.main.bundleIdentifier ?? "", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        req.setValue("routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline,routes.legs.steps.navigationInstruction,routes.legs.steps.distanceMeters,routes.legs.steps.endLocation,routes.legs.steps.transitDetails",
                     forHTTPHeaderField: "X-Goog-FieldMask")
        var body: [String: Any] = [
            "origin": pointJson(origin), "destination": pointJson(dest),
            "travelMode": mode.rawValue, "languageCode": "en-US", "units": "METRIC",
        ]
        if mode == .drive { body["routingPreference"] = "TRAFFIC_AWARE" }
        if mode != .transit { body["computeAlternativeRoutes"] = true }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return RouteFetch(routes: [], error: "No response") }
            if !(200...299).contains(http.statusCode) {
                // Surface Google's error message (e.g. "requests to this API ... are blocked").
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                    .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
                return RouteFetch(routes: [], error: msg ?? "Routes API error \(http.statusCode)")
            }
            let routes = parseRoutes(data)
            return RouteFetch(routes: routes, error: routes.isEmpty ? "No route for this mode" : nil)
        } catch {
            return RouteFetch(routes: [], error: error.localizedDescription)
        }
    }

    private static func pointJson(_ c: CLLocationCoordinate2D) -> [String: Any] {
        ["location": ["latLng": ["latitude": c.latitude, "longitude": c.longitude]]]
    }

    private static func parseRoutes(_ data: Data) -> [RouteResult] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let routes = root["routes"] as? [[String: Any]] else { return [] }
        return routes.compactMap { route in
            guard let poly = route["polyline"] as? [String: Any],
                  let encoded = poly["encodedPolyline"] as? String, !encoded.isEmpty else { return nil }
            var steps: [RouteStep] = []
            for leg in (route["legs"] as? [[String: Any]] ?? []) {
                for s in (leg["steps"] as? [[String: Any]] ?? []) { steps.append(parseStep(s)) }
            }
            let dur = Int((route["duration"] as? String ?? "").replacingOccurrences(of: "s", with: "")) ?? 0
            return RouteResult(points: decodePolyline(encoded),
                               distanceMeters: route["distanceMeters"] as? Int ?? 0,
                               durationSeconds: dur,
                               steps: steps.filter { !$0.instruction.isEmpty })
        }
    }

    private static func parseStep(_ step: [String: Any]) -> RouteStep {
        let nav = step["navigationInstruction"] as? [String: Any]
        var instr = nav?["instructions"] as? String ?? ""
        if instr.isEmpty, let t = step["transitDetails"] as? [String: Any] {
            let line = (t["transitLine"] as? [String: Any]).flatMap {
                let short = $0["nameShort"] as? String ?? ""
                return short.isEmpty ? ($0["name"] as? String) : short
            } ?? ""
            let headsign = t["headsign"] as? String ?? ""
            if !line.isEmpty { instr = "Take \(line)" + (headsign.isEmpty ? "" : " toward \(headsign)") }
        }
        let end = (step["endLocation"] as? [String: Any])?["latLng"] as? [String: Any]
        return RouteStep(instruction: instr,
                         maneuver: step["transitDetails"] != nil ? "TRANSIT" : (nav?["maneuver"] as? String ?? ""),
                         distanceMeters: step["distanceMeters"] as? Int ?? 0,
                         endLat: end?["latitude"] as? Double ?? 0, endLng: end?["longitude"] as? Double ?? 0)
    }

    /// Shortest distance (m) from a point to a polyline — off-route detection.
    static func distanceToPath(_ p: CLLocationCoordinate2D, _ path: [CLLocationCoordinate2D]) -> Double {
        guard !path.isEmpty else { return .greatestFiniteMagnitude }
        if path.count == 1 { return segDist(p, path[0], path[0]) }
        var minD = Double.greatestFiniteMagnitude
        for i in 0..<(path.count - 1) { minD = min(minD, segDist(p, path[i], path[i + 1])) }
        return minD
    }

    private static func segDist(_ p: CLLocationCoordinate2D, _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let mPerLat = 111_320.0
        let mPerLng = 111_320.0 * cos(a.latitude * .pi / 180)
        let px = (p.longitude - a.longitude) * mPerLng, py = (p.latitude - a.latitude) * mPerLat
        let bx = (b.longitude - a.longitude) * mPerLng, by = (b.latitude - a.latitude) * mPerLat
        let len2 = bx * bx + by * by
        let t = len2 == 0 ? 0 : max(0, min(1, (px * bx + py * by) / len2))
        let dx = px - t * bx, dy = py - t * by
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Standard Google encoded-polyline decoder.
    static func decodePolyline(_ encoded: String) -> [CLLocationCoordinate2D] {
        var poly: [CLLocationCoordinate2D] = []
        let chars = Array(encoded.unicodeScalars)
        var index = 0, lat = 0, lng = 0
        while index < chars.count {
            var shift = 0, result = 0, b: Int
            repeat { b = Int(chars[index].value) - 63; index += 1; result |= (b & 0x1f) << shift; shift += 5 } while b >= 0x20
            lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            shift = 0; result = 0
            repeat { b = Int(chars[index].value) - 63; index += 1; result |= (b & 0x1f) << shift; shift += 5 } while b >= 0x20
            lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            poly.append(CLLocationCoordinate2D(latitude: Double(lat) / 1e5, longitude: Double(lng) / 1e5))
        }
        return poly
    }
}
