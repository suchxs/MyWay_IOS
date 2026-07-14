// Turn-by-turn navigation state (MainActivity's directions/nav logic). Fetches routes, draws the
// selected polyline, and — once navigating — tracks the current step by proximity, speaks it, and
// re-fetches when you drift off-route.
import SwiftUI
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
    @Published var currentStep = 0
    @Published var distanceToNext = 0
    @Published var errorText: String?

    var points: [CLLocationCoordinate2D] { routes.indices.contains(selected) ? routes[selected].points : [] }
    var route: RouteResult? { routes.indices.contains(selected) ? routes[selected] : nil }

    private let speaker = AVSpeechSynthesizer()
    private var lastSpokenStep = -1
    private var rerouting = false
    private var offRouteCount = 0
    var voiceEnabled = true

    func plan(to dest: CLLocationCoordinate2D, name: String, from origin: CLLocationCoordinate2D?) {
        destination = dest; destName = name; selected = 0; navigating = false
        fetch(from: origin)
    }

    func setMode(_ m: TravelMode, from origin: CLLocationCoordinate2D?) {
        mode = m; fetch(from: origin)
    }

    func fetch(from origin: CLLocationCoordinate2D?) {
        guard let dest = destination else { return }
        guard let origin else { errorText = "Waiting for your location…"; return }
        loading = true; errorText = nil
        Task {
            let result = await Directions.fetchRoute(origin: origin, dest: dest, mode: mode)
            self.routes = result.routes; self.selected = 0; self.loading = false; self.errorText = result.error
        }
    }

    func startNav() {
        guard route != nil else { return }
        navigating = true; currentStep = 0; lastSpokenStep = -1
        speakStep()
    }

    func stop() {
        navigating = false; routes = []; destination = nil; destName = ""
        speaker.stopSpeaking(at: .immediate)
    }

    /// Feed each GPS fix in while navigating: advance the step and reroute if we drift.
    func onLocation(_ loc: CLLocation) {
        guard navigating, let route else { return }
        let here = loc.coordinate

        // Off-route → reroute once (needs a few consecutive misses to avoid GPS jitter).
        let offBy = Directions.distanceToPath(here, route.points)
        if offBy > 50 {
            offRouteCount += 1
            if offRouteCount >= 3, !rerouting {
                rerouting = true; offRouteCount = 0
                Task {
                    let r = await Directions.fetchRoute(origin: here, dest: destination!, mode: mode)
                    if !r.routes.isEmpty { self.routes = r.routes; self.selected = 0; self.currentStep = 0; self.lastSpokenStep = -1; self.speakStep() }
                    self.rerouting = false
                }
            }
        } else { offRouteCount = 0 }

        // Advance when we're within 25m of the current step's end.
        guard currentStep < route.steps.count else { return }
        let step = route.steps[currentStep]
        let end = CLLocation(latitude: step.endLat, longitude: step.endLng)
        distanceToNext = Int(loc.distance(from: end))
        if distanceToNext < 25, currentStep < route.steps.count - 1 {
            currentStep += 1
            speakStep()
        }
    }

    private func speakStep() {
        guard voiceEnabled, let route, route.steps.indices.contains(currentStep), lastSpokenStep != currentStep else { return }
        lastSpokenStep = currentStep
        let text = route.steps[currentStep].instruction
        guard !text.isEmpty else { return }
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
