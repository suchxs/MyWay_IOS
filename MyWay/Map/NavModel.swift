// Turn-by-turn navigation (MainActivity's directions/nav camera + reroute). Google-Maps-style follow:
// on each fix, animate the camera to (position, zoom 17.5, tilt 50°, heading = direction of travel),
// advance the step within 25 m of its end (with voice), and reroute when >50 m off the path.
import SwiftUI
import GoogleMaps
import CoreLocation
import AVFoundation

@MainActor
final class NavModel: ObservableObject {
    @Published var destination: CLLocationCoordinate2D?
    @Published var destName = ""
    @Published var mode: TravelMode = .drive
    @Published var routes: [RouteResult] = []
    @Published var selected = 0
    @Published var loading = false
    @Published var navigating = false
    @Published var following = true           // false once the user pans away → shows Recenter
    @Published var currentStep = 0
    @Published var distanceToNext = 0
    @Published var errorText: String?
    @Published var followCamera: GMSCameraPosition?
    @Published var traveledIndex = 0          // nearest route point → trims the drawn line to the road ahead

    var voiceEnabled = true
    private var lastBearing: Double = 0
    private var lastReroute = Date.distantPast
    private var offRouteCount = 0
    private var rerouting = false
    private let speaker = AVSpeechSynthesizer()
    private var lastSpokenStep = -1

    var route: RouteResult? { routes.indices.contains(selected) ? routes[selected] : nil }
    var points: [CLLocationCoordinate2D] {
        guard let r = route else { return [] }
        guard navigating, traveledIndex > 0, traveledIndex < r.points.count else { return r.points }
        return Array(r.points[traveledIndex...])
    }
    var currentInstruction: RouteStep? { route?.steps.indices.contains(currentStep) == true ? route!.steps[currentStep] : nil }
    var nextInstruction: RouteStep? { route?.steps.indices.contains(currentStep + 1) == true ? route!.steps[currentStep + 1] : nil }

    /// Remaining distance = the steps from here to the end.
    var remainingMeters: Int { route.map { $0.steps.dropFirst(currentStep).reduce(0) { $0 + $1.distanceMeters } } ?? 0 }
    var arrivalClock: String {
        guard let r = route else { return "" }
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: Date().addingTimeInterval(Double(r.durationSeconds)))
    }

    // ── Planning ──────────────────────────────────────────────────────────────────
    func plan(to dest: CLLocationCoordinate2D, name: String, from origin: CLLocationCoordinate2D?) {
        destination = dest; destName = name; selected = 0; navigating = false
        fetch(from: origin)
    }
    func setMode(_ m: TravelMode, from origin: CLLocationCoordinate2D?) { mode = m; fetch(from: origin) }

    func fetch(from origin: CLLocationCoordinate2D?) {
        guard let dest = destination else { return }
        guard let origin else { errorText = "Waiting for your location…"; return }
        loading = true; errorText = nil
        Task {
            let result = await Directions.fetchRoute(origin: origin, dest: dest, mode: mode)
            self.routes = result.routes; self.selected = 0; self.loading = false; self.errorText = result.error
        }
    }

    // ── Navigation ────────────────────────────────────────────────────────────────
    func startNav(from loc: CLLocation?) {
        guard route != nil else { return }
        navigating = true; following = true; currentStep = 0; lastSpokenStep = -1; traveledIndex = 0
        offRouteCount = 0; rerouting = false; lastReroute = Date()
        speakStep()
        if let loc { updateFollow(loc) }
    }

    func stop() {
        navigating = false; following = true
        routes = []; destination = nil; destName = ""; followCamera = nil
        speaker.stopSpeaking(at: .immediate)
    }

    func userPanned() { if navigating { following = false } }
    func recenter(_ loc: CLLocation?) { following = true; if let loc { updateFollow(loc) } }

    func onLocation(_ loc: CLLocation) {
        guard navigating, let route else { return }
        let here = loc.coordinate

        // Advance the "nearest point" forward-only so the drawn line trims to the road ahead.
        if traveledIndex < route.points.count {
            var best = traveledIndex, bestD = Double.greatestFiniteMagnitude
            for i in traveledIndex..<route.points.count {
                let d = loc.distance(from: CLLocation(latitude: route.points[i].latitude, longitude: route.points[i].longitude))
                if d < bestD { bestD = d; best = i }
                if d > bestD + 200 { break }   // stop once we're clearly moving away
            }
            traveledIndex = best
        }

        let off = Directions.distanceToPath(here, route.points)
        if off > 50 {
            offRouteCount += 1
            if offRouteCount >= 2, !rerouting, Date().timeIntervalSince(lastReroute) > 8 { reroute(from: here, announce: true) }
        } else {
            offRouteCount = 0
            if mode == .drive, !rerouting, Date().timeIntervalSince(lastReroute) > 90 { reroute(from: here, announce: false) }
        }

        let bearing = loc.course >= 0 ? loc.course : lastBearing
        lastBearing = bearing
        if following { updateFollow(loc, bearing: bearing) }

        guard currentStep < route.steps.count else { return }
        let step = route.steps[currentStep]
        guard step.endLat != 0 || step.endLng != 0 else { return }
        distanceToNext = Int(loc.distance(from: CLLocation(latitude: step.endLat, longitude: step.endLng)))
        if distanceToNext < 25 {
            currentStep += 1
            if currentStep < route.steps.count { speakStep() } else { speak("You have arrived at your destination") }
        }
    }

    private func updateFollow(_ loc: CLLocation, bearing: Double? = nil) {
        let b = bearing ?? (loc.course >= 0 ? loc.course : lastBearing)
        followCamera = GMSCameraPosition(target: loc.coordinate, zoom: 17.5, bearing: b, viewingAngle: 50)
    }

    private func reroute(from here: CLLocationCoordinate2D, announce: Bool) {
        guard let dest = destination, !rerouting else { return }
        rerouting = true; lastReroute = Date()
        if announce { speak("Rerouting") }
        Task {
            let r = await Directions.fetchRoute(origin: here, dest: dest, mode: mode)
            self.rerouting = false
            guard self.navigating, !r.routes.isEmpty else { return }
            self.routes = r.routes; self.selected = 0; self.currentStep = 0; self.offRouteCount = 0; self.traveledIndex = 0
            self.lastSpokenStep = -1; self.speakStep()
        }
    }

    private func speakStep() {
        guard voiceEnabled, let route, route.steps.indices.contains(currentStep), lastSpokenStep != currentStep else { return }
        lastSpokenStep = currentStep
        speak(route.steps[currentStep].instruction)
    }

    private func speak(_ text: String) {
        guard voiceEnabled, !text.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
        let utt = AVSpeechUtterance(string: text)
        utt.voice = AVSpeechSynthesisVoice(language: "en-US")
        speaker.speak(utt)
    }
}

func formatDistance(_ meters: Int) -> String {
    meters >= 1000 ? String(format: "%.1f km", Double(meters) / 1000) : "\(meters) m"
}
func formatDuration(_ seconds: Int) -> String {
    let m = seconds / 60
    return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(max(1, m)) min"
}
