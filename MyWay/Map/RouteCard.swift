// DirectionsUi.kt → SwiftUI. The bottom route card: mode picker, ETA/distance, route alternatives,
// Start/Stop navigation, and the live turn-by-turn banner while navigating.
import SwiftUI
import CoreLocation

struct RouteCard: View {
    @ObservedObject var nav: NavModel
    var origin: () -> CLLocationCoordinate2D?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 10) {
            if nav.navigating { navBanner } else { planner }
        }
        .padding(14)
        .background(Brand.surface(scheme == .dark))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 12)
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    // ── Planner (before navigation) ──────────────────────────────────────────────
    private var planner: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Directions to").font(.caption).foregroundColor(.secondary)
                    Text(nav.destName.isEmpty ? "Destination" : nav.destName).font(.headline).lineLimit(1)
                }
                Spacer()
                Button { nav.stop() } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).font(.title2) }
            }

            Picker("Mode", selection: Binding(get: { nav.mode }, set: { nav.setMode($0, from: origin()) })) {
                ForEach(TravelMode.allCases) { m in
                    Label(m.label, systemImage: m.systemImage).tag(m)
                }
            }.pickerStyle(.segmented)

            if nav.loading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let r = nav.route {
                HStack(spacing: 16) {
                    Label(formatDuration(r.durationSeconds), systemImage: "clock").bold()
                    Label(formatDistance(r.distanceMeters), systemImage: "arrow.left.and.right")
                    Spacer()
                }.font(.subheadline)

                if nav.routes.count > 1 {
                    HStack {
                        ForEach(Array(nav.routes.enumerated()), id: \.offset) { i, route in
                            Button {
                                nav.selected = i
                            } label: {
                                Text("\(formatDuration(route.durationSeconds))")
                                    .font(.caption).bold()
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(i == nav.selected ? Brand.teal.opacity(0.2) : Color.gray.opacity(0.12))
                                    .foregroundColor(i == nav.selected ? Brand.tealDeep : .secondary)
                                    .clipShape(Capsule())
                            }
                        }
                        Spacer()
                    }
                }

                Button { nav.startNav() } label: {
                    Label("Start", systemImage: "location.north.line.fill").bold().frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(Brand.teal)
            } else if let err = nav.errorText {
                Text(err).foregroundColor(.secondary).font(.footnote).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No route found").foregroundColor(.secondary).font(.subheadline)
            }
        }
    }

    // ── Live navigation banner ────────────────────────────────────────────────────
    private var navBanner: some View {
        let step = nav.route?.steps.indices.contains(nav.currentStep) == true ? nav.route!.steps[nav.currentStep] : nil
        return VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: maneuverIcon(step?.maneuver ?? "")).font(.title).foregroundColor(Brand.tealDeep)
                VStack(alignment: .leading, spacing: 2) {
                    Text(step?.instruction ?? "Proceed to destination").font(.headline)
                    if nav.distanceToNext > 0 { Text(formatDistance(nav.distanceToNext)).font(.subheadline).foregroundColor(.secondary) }
                }
                Spacer()
            }
            HStack {
                Button { nav.voiceEnabled.toggle() } label: {
                    Image(systemName: nav.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                Spacer()
                Button(role: .destructive) { nav.stop() } label: { Label("End", systemImage: "xmark").bold() }
                    .buttonStyle(.borderedProminent).tint(Color(hex: 0xEF4444)).controlSize(.small)
            }
        }
    }

    private func maneuverIcon(_ m: String) -> String {
        let s = m.uppercased()
        if s.contains("LEFT") { return "arrow.turn.up.left" }
        if s.contains("RIGHT") { return "arrow.turn.up.right" }
        if s.contains("UTURN") { return "arrow.uturn.down" }
        if s.contains("TRANSIT") { return "bus.fill" }
        if s.contains("MERGE") || s.contains("RAMP") { return "arrow.merge" }
        return "arrow.up"
    }
}
