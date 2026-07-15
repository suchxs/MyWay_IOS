// MainActivity.kt → SwiftUI. The hub: Google map + saved pins, a slide-in drawer, a bottom stats/action
// card, and a place-detail sheet. Trips / live-location / turn-by-turn directions are scaffolded for the
// next pass (see SETUP.md "Deferred"); everything on the personal-map + navigation-drawer path is here.
import SwiftUI
import GoogleMaps
import FirebaseAuth

struct LandmarkTarget: Identifiable { let id: String; let name: String; let coord: CLLocationCoordinate2D }

struct MapHomeView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var loc = LocationManager()
    @StateObject private var navModel = NavModel()
    @StateObject private var mapHolder = MapHolder()
    @ObservedObject private var trip = TripManager.shared
    @ObservedObject private var profiles = ProfileStore.shared

    @State private var drawerOpen = false
    @State private var tracking = true
    @State private var camera: GMSCameraPosition?
    @State private var didCenter = false

    @State private var selected: SavedPlace?
    @State private var nav: SidebarDestination?
    @State private var showRoster = false
    @State private var landmark: LandmarkTarget?
    @State private var showSearch = false
    @State private var showShareSheet = false
    @State private var pinMode = false
    // Save-waypoint dialog (pin-mode tap or long-press): drop at the tapped point, ask name + notes.
    @State private var savePinCoord: CLLocationCoordinate2D?
    @State private var pinName = ""
    @State private var pinNote = ""
    @State private var tripPinTarget: TripPin?
    @State private var routeIsTrip = false        // current route is the shared trip direction (group)
    @State private var routeIsPlan = false        // …and it's driven by the Plan (auto, no prompt)
    @State private var autoStartNav = false
    @State private var directionChoice: DirTarget?    // "group vs just me" prompt when starting directions on a trip
    @State private var incomingDest: TripDest?        // someone else set a direction → accept/dismiss

    private var uid: String { Auth.auth().currentUser?.uid ?? "" }
    private var myTag: String { state.userTag(uid) }

    var body: some View {
        ZStack(alignment: .bottom) {
            GoogleMapView(
                places: state.places,
                pinHue: state.pinHue,
                pinIcon: state.pinIcon,
                pencilGlyph: state.pencilIcon,
                dark: state.darkMode,
                showPersonal: trip.currentGid == nil,
                members: trip.members,
                liveShares: trip.visibleShares,
                tripPins: trip.pins,
                dest: trip.dest,
                routePoints: navModel.points,
                tempPin: savePinCoord,
                myUid: uid,
                holder: mapHolder,
                navFollow: navModel.navigating ? navModel.followCamera : nil,
                camera: $camera,
                onTapMarker: { p in selected = p; center(on: p.coordinate) },
                onLongPress: { c in pinMode = false; savePinCoord = c },
                onTapPOI: { id, name, coord in
                    if pinMode { savePinCoord = coord; return }
                    landmark = LandmarkTarget(id: id, name: name, coord: coord); center(on: coord)
                },
                onTap: { c in if pinMode { savePinCoord = c } },
                onTapTripPin: { tripPinTarget = $0 },
                onUserPan: { navModel.userPanned() }
            )
            .ignoresSafeArea()

            // Trip guide arrows — point at off-screen members while on a trip.
            if trip.currentGid != nil, !navModel.navigating {
                TripArrowsView(members: trip.members, myUid: uid, holder: mapHolder) { center(on: $0) }
                    .allowsHitTesting(true)
            }

            if navModel.navigating {
                VStack { NavBanner(nav: navModel, kind: directionKind); Spacer() }
                NavFooter(nav: navModel) { navModel.stop() }
            } else {
                topBar
                if navModel.destination != nil {
                    RoutePlanner(nav: navModel, origin: { loc.location?.coordinate }, kind: directionKind,
                                 onStart: { navModel.startNav(from: loc.location) })
                } else {
                    bottomCard
                }
            }

            sideButtons

            if drawerOpen { drawerOverlay }
        }
        .onChange(of: navModel.navigating) { on in loc.navMode(on); if on { mapHolder.setHeading(false) } }
        .onChange(of: trip.currentGid) { gid in if gid != nil { nav = nil } }   // joining a trip → back to the map
        .onChange(of: navModel.routes.count) { _ in
            fitRoute()
            if autoStartNav, navModel.route != nil { autoStartNav = false; navModel.startNav(from: loc.location) }
        }
        .onChange(of: navModel.selected) { _ in fitRoute() }
        // React to the shared trip direction (mirrors MainActivity.onTripDestChanged): plan stops auto-route,
        // your own direction follows itself, and someone ELSE's manual direction prompts to accept/dismiss.
        .onChange(of: trip.dest) { onTripDestChanged($0) }
        .confirmationDialog("Directions to \(directionChoice?.name ?? "")",
                            isPresented: Binding(get: { directionChoice != nil }, set: { if !$0 { directionChoice = nil } }),
                            titleVisibility: .visible) {
            Button("Set as group direction") { chooseTripDirection() }
            Button("Just me (solo)") { chooseSoloDirection() }
            Button("Cancel", role: .cancel) { directionChoice = nil }
        } message: { Text("Share this direction with the whole trip, or navigate it just for yourself?") }
        .sheet(item: $incomingDest) { d in
            IncomingDirectionSheet(dest: d, byPhoto: trip.members.first { $0.uid == d.by }?.photo ?? "",
                                   onJoin: { incomingDest = nil; followSharedDest(d, isPlan: false) },
                                   onDismiss: { incomingDest = nil; if let gid = trip.currentGid { Trip.endTripDestForMe(gid, uid: uid) } })
        }
        .onAppear {
            loc.start()
            if myTag.isEmpty, !uid.isEmpty {
                Profiles.fetchTag(uid) { if let t = $0 { state.setUserTag(uid, t) } }
            }
        }
        .onReceive(loc.$location.compactMap { $0 }) { l in
            navModel.onLocation(l)
            guard !didCenter else { return }
            didCenter = true
            camera = GMSCameraPosition(latitude: l.coordinate.latitude, longitude: l.coordinate.longitude, zoom: 15)
        }
        .sheet(item: $selected) { place in
            PlaceSheet(place: place, myUid: uid, myTag: myTag,
                       onDirections: { c, name in requestDirections(c, name) },
                       onViewLandmark: { p in landmark = LandmarkTarget(id: p.placeId, name: p.name, coord: p.coordinate) })
                .environmentObject(state)
        }
        .sheet(item: $landmark) { t in
            LandmarkSheet(placeID: t.id, fallbackName: t.name, coordinate: t.coord, myUid: uid, myTag: myTag,
                          onDirections: { c, name in requestDirections(c, name) })
                .environmentObject(state)
        }
        .sheet(isPresented: $showShareSheet) { ShareLocationSheet(myUid: uid, myTag: myTag) }
        .sheet(isPresented: $showSearch) {
            PlaceSearchView { id, name, coord in
                center(on: coord)
                if !id.isEmpty { landmark = LandmarkTarget(id: id, name: name, coord: coord) }
            }
        }
        .alert("📌 Save Waypoint", isPresented: Binding(get: { savePinCoord != nil }, set: { if !$0 { cancelPin() } })) {
            TextField("Name", text: $pinName)
            TextField("Notes", text: $pinNote)
            Button("Save") { savePin() }
            Button("Cancel", role: .cancel) { cancelPin() }
        } message: {
            if let c = savePinCoord { Text(String(format: "%.6f, %.6f", c.latitude, c.longitude)) }
        }
        .sheet(item: $tripPinTarget) { pin in
            TripPinActionsSheet(pin: pin, gid: trip.currentGid ?? "",
                                onDirections: { requestDirections(CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng), pin.name.isEmpty ? "Shared pin" : pin.name) })
        }
        .fullScreenCover(item: $nav) { destination in
            NavigationStack {
                destinationView(destination)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button { nav = nil } label: { Label("Back", systemImage: "chevron.left") }
                        }
                    }
            }
        }
        .sheet(isPresented: $showRoster) {
            TripRosterView(trip: trip, myUid: uid, myTag: myTag,
                           onFollowDest: { d in showRoster = false; followSharedDest(d, isPlan: !d.planItemId.isEmpty) },
                           onFocusMember: { coord in camera = GMSCameraPosition(latitude: coord.latitude, longitude: coord.longitude, zoom: 16) })
        }
    }

    // ── Top bar: menu + search ──────────────────────────────────────────────────────
    private var topBar: some View {
        VStack {
            HStack(spacing: 10) {
                Button { withAnimation(.spring) { drawerOpen = true } } label: {
                    Image("Logo").resizable().scaledToFit().padding(7)
                        .frame(width: 46, height: 46).background(Brand.surface(state.darkMode)).clipShape(Circle())
                        .shadow(radius: 4)
                }
                Button { showSearch = true } label: {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        Text("Search places").foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14).frame(height: 46)
                    .background(Brand.surface(state.darkMode)).clipShape(Capsule()).shadow(radius: 4)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8)

            if trip.currentGid != nil { tripLiveBar.padding(.horizontal, 16).padding(.top, 8) }
            Spacer()
        }
    }

    // Live-trip banner (MainActivity.TripLiveBar) — tap for roster, Leave to go offline.
    private var tripLiveBar: some View {
        HStack(spacing: 10) {
            Circle().fill(Color.red).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(trip.groupName.isEmpty ? "Live trip" : trip.groupName).font(.subheadline).bold()
                Text("\(trip.members.count) sharing").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Button("Leave") { trip.leaveTrip() }
                .font(.caption).bold().foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color(hex: 0xEF4444)).clipShape(Capsule())
        }
        .padding(.horizontal, 14).frame(height: 52)
        .background(Brand.surface(state.darkMode)).clipShape(RoundedRectangle(cornerRadius: 16)).shadow(radius: 4)
        .onTapGesture { showRoster = true }
    }

    // ── Bottom card (BottomCard.kt) ──────────────────────────────────────────────────
    private var bottomCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "mappin.circle.fill").foregroundColor(Brand.tealDeep)
                VStack(alignment: .leading, spacing: 2) {
                    Text("CURRENT LOCATION").font(.system(size: 10, weight: .bold)).foregroundColor(Brand.tealDeep)
                    Text(loc.address).font(.system(size: 13, weight: .bold)).lineLimit(2)
                }
                Spacer()
            }
            if pinMode {
                Text("Tap the map to drop a pin")
                    .font(.caption).bold().foregroundColor(Brand.tealDeep)
                    .frame(maxWidth: .infinity).padding(.top, 8)
            }
            HStack(spacing: 8) {
                actionButton(pinMode ? "xmark" : "mappin", pinMode ? "Cancel" : "Pin") { pinMode.toggle() }
                actionButton(trip.sharingLive ? "dot.radiowaves.left.and.right" : "square.and.arrow.up",
                             trip.sharingLive ? "Live" : "Share") { showShareSheet = true }
            }.padding(.top, 12)

            if tracking, let c = loc.location {
                HStack(spacing: 6) {
                    stat("LAT", String(format: "%.4f", c.coordinate.latitude))
                    stat("LNG", String(format: "%.4f", c.coordinate.longitude))
                    stat("ALT", String(format: "%.0fm", c.altitude))
                    stat("ACC", String(format: "%.0fm", c.horizontalAccuracy))
                    stat("SPD", String(format: "%.0fkm/h", max(0, c.speed) * 3.6))
                }.padding(.top, 12)
            }
        }
        .padding(14)
        .background(Brand.surface(state.darkMode))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 12)
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private func actionButton(_ sys: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Image(systemName: sys); Text(label).bold() }
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Brand.teal.opacity(0.12)).foregroundColor(Brand.tealDeep)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .bold)).foregroundColor(Brand.tealDeep)
            Text(value).font(.system(size: 12, weight: .bold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8).padding(.horizontal, 6)
        .background(Brand.teal.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // ── Drawer overlay ───────────────────────────────────────────────────────────────
    private var drawerOverlay: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { withAnimation { drawerOpen = false } }
            Sidebar(
                userName: profiles.name(uid), userTag: profiles.tag(uid).isEmpty ? myTag : profiles.tag(uid),
                userPhoto: profiles.photo(uid), userBanner: profiles.banner(uid),
                tracking: $tracking,
                onNavigate: { dest in drawerOpen = false; nav = dest },
                onLogout: { drawerOpen = false; AuthService.signOut() }
            )
            .environmentObject(state)
            .transition(.move(edge: .leading))
        }
    }

    // Compass (resets north when the map is rotated) + Recenter (snaps nav follow back to you).
    private var sideButtons: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    // Compass — only when the map is rotated, not navigating, and not in heading mode.
                    if !navModel.navigating, !mapHolder.headingMode, abs(mapHolder.bearing) > 0.5 {
                        circleButton("location.north.line.fill", tint: .primary) { mapHolder.resetNorth() }
                            .rotationEffect(.degrees(-mapHolder.bearing))
                    }
                    // Heading-up ("gyro") toggle — rotates the map to the way you're facing. Only off-nav.
                    if !navModel.navigating, loc.location != nil {
                        circleButton("safari.fill", tint: mapHolder.headingMode ? Brand.teal : .primary) {
                            mapHolder.setHeading(!mapHolder.headingMode)
                        }
                    }
                    // Recenter follow while navigating; My Location otherwise (always available, like Google Maps).
                    if navModel.navigating {
                        if !navModel.following { circleButton("location.fill", tint: Brand.teal) { navModel.recenter(loc.location) } }
                    } else {
                        circleButton("location.fill", tint: Brand.teal) { if let l = loc.location { center(on: l.coordinate) } }
                    }
                }.padding(.trailing, 16)
            }
        }
        .padding(.bottom, navModel.navigating || navModel.destination != nil ? 140 : 200)
    }

    private func circleButton(_ sys: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: sys).font(.title3).foregroundColor(tint)
                .frame(width: 46, height: 46).background(Brand.surface(state.darkMode)).clipShape(Circle()).shadow(radius: 4)
        }
    }

    // Route overview: frame the whole route once it's fetched (before you press Start).
    private func fitRoute() {
        guard !navModel.navigating, let r = navModel.route, r.points.count > 1 else { return }
        var pts = r.points
        if let me = loc.location?.coordinate { pts.append(me) }
        mapHolder.fit(pts)
    }

    private var directionKind: String { routeIsPlan ? "Plan stop" : (routeIsTrip ? "Group direction" : "Solo") }

    private func center(on coord: CLLocationCoordinate2D) {
        camera = GMSCameraPosition(latitude: coord.latitude, longitude: coord.longitude, zoom: 16)
    }

    // On a trip → the pin belongs to the shared session (Trip.sharePin); otherwise it's a personal pin.
    private func savePin() {
        guard let c = savePinCoord else { return }
        if let gid = trip.currentGid {
            Trip.sharePin(gid, fromUid: uid, fromTag: myTag, fromPhoto: state.userPhoto(uid),
                          lat: c.latitude, lng: c.longitude, name: pinName.trimmed, note: pinNote.trimmed)
        } else {
            state.saveLocation(c)
            let key = locationKey(c.latitude, c.longitude)
            if !pinName.trimmed.isEmpty { state.saveName(key, pinName.trimmed) }
            if !pinNote.trimmed.isEmpty { state.saveNote(key, pinNote.trimmed) }
        }
        cancelPin()
    }

    private func cancelPin() { savePinCoord = nil; pinName = ""; pinNote = ""; pinMode = false }

    // ── Directions / trip direction flow (MainActivity.startDirections + onTripDestChanged) ──────────
    private func requestDirections(_ coord: CLLocationCoordinate2D, _ name: String) {
        if trip.currentGid != nil { directionChoice = DirTarget(coord: coord, name: name) }   // ask: group or solo?
        else { routeIsTrip = false; routeIsPlan = false; navModel.plan(to: coord, name: name, from: loc.location?.coordinate) }
    }

    private func chooseTripDirection() {
        guard let dc = directionChoice, let gid = trip.currentGid else { return }
        directionChoice = nil
        let planActive = trip.plan != nil && trip.plan?.archived == false
        if planActive { Trip.prependPlanItem(gid, name: dc.name, lat: dc.coord.latitude, lng: dc.coord.longitude, actorUid: uid, actorTag: myTag) { _ in } }
        else { Trip.setTripDest(gid, lat: dc.coord.latitude, lng: dc.coord.longitude, name: dc.name, byUid: uid, byTag: myTag) { _ in } }
        routeIsTrip = true; routeIsPlan = planActive
        navModel.plan(to: dc.coord, name: dc.name, from: loc.location?.coordinate)
    }

    private func chooseSoloDirection() {
        guard let dc = directionChoice else { return }
        directionChoice = nil
        routeIsTrip = false; routeIsPlan = false
        navModel.plan(to: dc.coord, name: dc.name, from: loc.location?.coordinate)
    }

    private func followSharedDest(_ d: TripDest, isPlan: Bool) {
        routeIsTrip = true; routeIsPlan = isPlan
        let wasNavigating = navModel.navigating
        navModel.plan(to: CLLocationCoordinate2D(latitude: d.lat, longitude: d.lng),
                      name: d.name.isEmpty ? (isPlan ? "Plan stop" : "Trip destination") : d.name, from: loc.location?.coordinate)
        autoStartNav = wasNavigating
    }

    private func onTripDestChanged(_ dest: TripDest?) {
        guard trip.currentGid != nil else { return }
        guard let d = dest else {
            if routeIsTrip { routeIsTrip = false; routeIsPlan = false; navModel.stop() }
            incomingDest = nil; return
        }
        // Already following this exact destination? do nothing.
        if routeIsTrip, let cur = navModel.destination, abs(cur.latitude - d.lat) < 1e-6, abs(cur.longitude - d.lng) < 1e-6 { incomingDest = nil; return }
        if !d.planItemId.isEmpty { followSharedDest(d, isPlan: true); return }   // plan-driven → auto (no prompt)
        if d.done.contains(uid) { incomingDest = nil; return }                   // I already dismissed/finished it
        if d.by == uid { routeIsTrip = true; routeIsPlan = false; return }       // I set it → already following
        incomingDest = d                                                         // someone else set it → prompt
    }

    @ViewBuilder
    private func destinationView(_ d: SidebarDestination) -> some View {
        switch d {
        case .friends:     FriendsView(myUid: uid, myTag: myTag)
        case .messages:    MessagesView(myUid: uid, myTag: myTag)
        case .collections: CollectionsView()
        case .waypoints:   WaypointsView(onFocus: { coord in nav = nil; center(on: coord) })
        case .settings:    SettingsView()
        case .profile:     ProfileView(uid: uid)
        }
    }
}

extension SidebarDestination: Identifiable { var id: Int { hashValue } }

struct DirTarget: Identifiable { let coord: CLLocationCoordinate2D; let name: String; var id: String { "\(coord.latitude),\(coord.longitude)" } }

// IncomingTripDirectionDialog → SwiftUI. Someone else set a group direction — accept or dismiss.
struct IncomingDirectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let dest: TripDest
    let byPhoto: String
    var onJoin: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            AvatarCircle(photoBase64: byPhoto, tag: dest.byTag, size: 64)
            Text("@\(dest.byTag.isEmpty ? "someone" : dest.byTag) set a group direction").font(.headline)
                .multilineTextAlignment(.center)
            Text(dest.name.isEmpty ? "Trip destination" : dest.name).foregroundColor(.secondary)
            HStack(spacing: 12) {
                Button("Dismiss") { onDismiss(); dismiss() }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                Button("Join") { onJoin(); dismiss() }.buttonStyle(.borderedProminent).tint(Brand.teal).frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .presentationDetents([.height(260)])
    }
}

// Action panel for a shared trip pin (TripPinActionsDialog) — any member can get directions, edit, or delete.
struct TripPinActionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let pin: TripPin
    let gid: String
    var onDirections: () -> Void
    @State private var editing = false
    @State private var note = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        AvatarCircle(photoBase64: pin.fromPhoto, tag: pin.fromTag, size: 28)
                        Text("Shared by @\(pin.fromTag)").font(.caption).foregroundColor(.secondary)
                    }
                    if !pin.note.isEmpty { Text("✎ \(pin.note)") }
                }
                Section {
                    Button { onDirections(); dismiss() } label: { Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill") }
                    Button { note = pin.note; editing = true } label: { Label("Edit note", systemImage: "pencil") }
                    Button(role: .destructive) { Trip.deletePin(gid, pinId: pin.id) { _ in }; dismiss() } label: { Label("Delete", systemImage: "trash") }
                }
            }
            .navigationTitle(pin.name.isEmpty ? "Shared pin" : pin.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .alert("Edit note", isPresented: $editing) {
                TextField("Note", text: $note)
                Button("Save") { Trip.updatePin(gid, pinId: pin.id, name: pin.name, note: note) { _ in }; dismiss() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
