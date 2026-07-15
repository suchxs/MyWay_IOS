// PlanUi.kt → SwiftUI. The shared trip plan: an ordered queue of objectives that auto-drives the group
// direction. The top not-finished item is "Next"; completing all archives the plan. Pause/resume.
import SwiftUI
import CoreLocation
import FirebaseFirestore

struct PlanView: View {
    @Environment(\.dismiss) private var dismiss
    let gid: String
    let actorUid: String
    let actorTag: String
    let tripPins: [TripPin]

    @State private var plan: TripPlan?
    @State private var planName = ""
    @State private var newObjective = ""
    @State private var showSearch = false
    @State private var pending: PendingObjective?     // a searched place waiting to be named + added
    @State private var reg: ListenerRegistration?

    struct PendingObjective { let name: String; let lat, lng: Double }

    var body: some View {
        NavigationStack {
            Group {
                if let plan, !plan.archived { activePlan(plan) } else { emptyPlan(archived: plan?.archived == true) }
            }
            .navigationTitle("Trip Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onAppear { reg = Trip.listenPlan(gid) { plan = $0 } }
            .onDisappear { reg?.remove() }
        }
    }

    private func emptyPlan(archived: Bool) -> some View {
        Form {
            Section {
                if archived, let plan { Text("“\(plan.name)” complete — \(plan.items.count) objectives done.").foregroundColor(.secondary) }
                TextField("Plan name", text: $planName)
                Button(archived ? "Start a new plan" : "Create plan") {
                    Trip.createPlan(gid, name: planName, actorUid: actorUid, actorTag: actorTag) { _ in }
                    planName = ""
                }.tint(Brand.teal)
            }
        }
    }

    private func activePlan(_ plan: TripPlan) -> some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text(plan.name).font(.headline)
                        Text("\(plan.items.filter { $0.finished }.count)/\(plan.items.count) done\(plan.paused ? " · paused" : "")")
                            .font(.caption).foregroundColor(plan.paused ? Color(hex: 0xEF4444) : .secondary)
                    }
                    Spacer()
                    Button {
                        Trip.setPlanPaused(gid, paused: !plan.paused, actorUid: actorUid, actorTag: actorTag) { _ in }
                    } label: { Label(plan.paused ? "Resume" : "Pause", systemImage: plan.paused ? "play.fill" : "pause.fill") }
                        .buttonStyle(.bordered)
                }
            }
            Section("Objectives") {
                ForEach(plan.items) { item in
                    let isNext = item.id == plan.activeItem?.id
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.name.isEmpty ? "Objective" : item.name)
                                .strikethrough(item.finished).foregroundColor(item.finished ? .secondary : .primary)
                                .fontWeight(isNext ? .bold : .regular)
                            if isNext, !plan.paused {
                                Label("Next stop", systemImage: "play.fill").font(.caption2).bold().foregroundColor(Brand.tealDeep)
                            }
                        }
                        Spacer()
                        Button(item.finished ? "Undo" : "Done") {
                            Trip.setItemFinished(gid, itemId: item.id, finished: !item.finished, actorUid: actorUid, actorTag: actorTag) { _ in }
                        }.tint(Brand.teal)
                    }
                }
            }
            Section("Add objective") {
                // Search a place (Android's AddObjectiveField) → pick → name the activity → add.
                Button { showSearch = true } label: { Label("Search a place", systemImage: "magnifyingglass") }.tint(Brand.teal)

                if let p = pending {
                    TextField("Name / activity", text: $newObjective)
                    Button {
                        addItem(name: newObjective.trimmed.isEmpty ? p.name : newObjective.trimmed, lat: p.lat, lng: p.lng)
                        pending = nil
                    } label: { Label("Add “\(newObjective.trimmed.isEmpty ? p.name : newObjective.trimmed)”", systemImage: "plus.circle.fill") }
                        .tint(Brand.teal)
                }

                if !tripPins.isEmpty {
                    ForEach(tripPins) { pin in
                        Button {
                            addItem(name: pin.name.isEmpty ? "Trip pin by @\(pin.fromTag)" : pin.name, lat: pin.lat, lng: pin.lng)
                        } label: { Label(pin.name.isEmpty ? "Trip pin by @\(pin.fromTag)" : pin.name, systemImage: "mappin") }
                    }
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            PlaceSearchView { _, name, coord in
                pending = PendingObjective(name: name, lat: coord.latitude, lng: coord.longitude)
                newObjective = name
            }
        }
    }

    private func addItem(name: String, lat: Double, lng: Double) {
        Trip.addPlanItem(gid, name: name, lat: lat, lng: lng, actorUid: actorUid, actorTag: actorTag) { _ in }
        newObjective = ""
    }
}
