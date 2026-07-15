// DirectionsUi.kt → SwiftUI. Three pieces of the navigation UI:
//  • RoutePlanner — bottom card before you start (mode, ETA, alternatives, Start)
//  • NavBanner    — top maneuver banner while navigating (big turn icon + instruction + distance)
//  • NavFooter    — bottom bar while navigating (ETA / remaining / exit)
import SwiftUI
import CoreLocation

struct RoutePlanner: View {
    @ObservedObject var nav: NavModel
    var origin: () -> CLLocationCoordinate2D?
    var kind: String = "Solo"
    var onStart: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Directions to").font(.caption).foregroundColor(.secondary)
                        Text(kind).font(.caption2).bold().foregroundColor(kind == "Solo" ? .secondary : Brand.tealDeep)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((kind == "Solo" ? Color.gray : Brand.teal).opacity(0.15)).clipShape(Capsule())
                    }
                    Text(nav.destName.isEmpty ? "Destination" : nav.destName).font(.headline).lineLimit(1)
                }
                Spacer()
                Button { nav.stop() } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).font(.title2) }
            }
            Picker("Mode", selection: Binding(get: { nav.mode }, set: { nav.setMode($0, from: origin()) })) {
                ForEach(TravelMode.allCases) { m in Label(m.label, systemImage: m.systemImage).tag(m) }
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
                            Button { nav.selected = i } label: {
                                Text(formatDuration(route.durationSeconds)).font(.caption).bold()
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(i == nav.selected ? Brand.teal.opacity(0.2) : Color.gray.opacity(0.12))
                                    .foregroundColor(i == nav.selected ? Brand.tealDeep : .secondary).clipShape(Capsule())
                            }
                        }
                        Spacer()
                    }
                }
                Button { onStart() } label: { Label("Start", systemImage: "location.north.line.fill").bold().frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(Brand.teal)
            } else if let err = nav.errorText {
                Text(err).foregroundColor(.secondary).font(.footnote).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No route found").foregroundColor(.secondary).font(.subheadline)
            }
        }
        .padding(14).background(Brand.surface(scheme == .dark)).clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 12).padding(.horizontal, 12).padding(.bottom, 8)
    }
}

struct NavBanner: View {
    @ObservedObject var nav: NavModel
    var kind: String = ""
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: maneuverIcon(nav.currentInstruction?.maneuver ?? "")).font(.system(size: 34, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if nav.distanceToNext > 0 { Text(formatDistance(nav.distanceToNext)).font(.title3).bold() }
                    if !kind.isEmpty, kind != "Solo" { Text(kind).font(.caption2).bold()
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Color.white.opacity(0.25)).clipShape(Capsule()) }
                }
                Text(nav.currentInstruction?.instruction ?? "Proceed to destination").font(.headline).lineLimit(2)
                if let next = nav.nextInstruction, !next.instruction.isEmpty {
                    HStack(spacing: 4) {
                        Text("then").font(.caption).foregroundColor(.white.opacity(0.8))
                        Image(systemName: maneuverIcon(next.maneuver)).font(.caption)
                        Text(next.instruction).font(.caption).lineLimit(1).foregroundColor(.white.opacity(0.9))
                    }
                }
            }
            Spacer()
            Button { nav.voiceEnabled.toggle() } label: {
                Image(systemName: nav.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill").font(.title3)
            }
        }
        .foregroundColor(.white)
        .padding(16).background(Brand.tealDeep).clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(radius: 8).padding(.horizontal, 12).padding(.top, 8)
    }
}

struct NavFooter: View {
    @ObservedObject var nav: NavModel
    var onExit: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text(nav.arrivalClock).font(.title3).bold().foregroundColor(Brand.tealDeep)
                Text("\(formatDuration(nav.route?.durationSeconds ?? 0)) · \(formatDistance(nav.remainingMeters))")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button(role: .destructive) { onExit() } label: { Label("Exit", systemImage: "xmark").bold() }
                .buttonStyle(.borderedProminent).tint(Color(hex: 0xEF4444))
        }
        .padding(16).background(Brand.surface(scheme == .dark)).clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 12).padding(.horizontal, 12).padding(.bottom, 8)
    }
}

func maneuverIcon(_ m: String) -> String {
    let s = m.uppercased()
    if s.contains("UTURN") { return "arrow.uturn.down" }
    if s.contains("LEFT") { return "arrow.turn.up.left" }
    if s.contains("RIGHT") { return "arrow.turn.up.right" }
    if s.contains("TRANSIT") { return "bus.fill" }
    if s.contains("MERGE") || s.contains("RAMP") || s.contains("FORK") { return "arrow.triangle.merge" }
    if s.contains("ROUNDABOUT") || s.contains("ROTARY") { return "arrow.clockwise.circle" }
    if s.contains("DESTINATION") { return "mappin.circle.fill" }
    return "arrow.up"
}
