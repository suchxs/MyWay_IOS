// MainActivity.kt → SwiftUI. The hub: Google map + saved pins, a slide-in drawer, a bottom stats/action
// card, and a place-detail sheet. Trips / live-location / turn-by-turn directions are scaffolded for the
// next pass (see SETUP.md "Deferred"); everything on the personal-map + navigation-drawer path is here.
import SwiftUI
import GoogleMaps
import FirebaseAuth

struct MapHomeView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var loc = LocationManager()
    @ObservedObject private var trip = TripManager.shared

    @State private var drawerOpen = false
    @State private var tracking = true
    @State private var camera: GMSCameraPosition?
    @State private var didCenter = false

    @State private var selected: SavedPlace?
    @State private var pendingDrop: CLLocationCoordinate2D?
    @State private var nav: SidebarDestination?
    @State private var showRoster = false

    private var uid: String { Auth.auth().currentUser?.uid ?? "" }
    private var myTag: String { state.userTag(uid) }

    var body: some View {
        ZStack(alignment: .bottom) {
            GoogleMapView(
                places: state.places,
                pinHue: state.pinHue,
                dark: state.darkMode,
                members: trip.currentGid != nil ? trip.members : [],
                tripPins: trip.currentGid != nil ? trip.pins : [],
                dest: trip.currentGid != nil ? trip.dest : nil,
                myUid: uid,
                camera: $camera,
                onTapMarker: { selected = $0 },
                onLongPress: { pendingDrop = $0 }
            )
            .ignoresSafeArea()

            topBar
            bottomCard

            if drawerOpen { drawerOverlay }
        }
        .onAppear {
            loc.start()
            if myTag.isEmpty, !uid.isEmpty {
                Profiles.fetchTag(uid) { if let t = $0 { state.setUserTag(uid, t) } }
            }
        }
        .onReceive(loc.$location.compactMap { $0 }) { l in
            guard !didCenter else { return }
            didCenter = true
            camera = GMSCameraPosition(latitude: l.coordinate.latitude, longitude: l.coordinate.longitude, zoom: 15)
        }
        .sheet(item: $selected) { place in
            PlaceSheet(place: place, myUid: uid, myTag: myTag).environmentObject(state)
        }
        .alert("Drop a pin here?", isPresented: .constant(pendingDrop != nil)) {
            Button("Save") { if let c = pendingDrop { state.saveLocation(c) }; pendingDrop = nil }
            Button("Cancel", role: .cancel) { pendingDrop = nil }
        }
        .fullScreenCover(item: $nav) { destination in
            NavigationStack { destinationView(destination) }
        }
        .sheet(isPresented: $showRoster) {
            TripRosterView(trip: trip, myUid: uid) { coord in
                camera = GMSCameraPosition(latitude: coord.latitude, longitude: coord.longitude, zoom: 16)
            }
        }
    }

    // ── Top bar: menu + search ──────────────────────────────────────────────────────
    private var topBar: some View {
        VStack {
            HStack(spacing: 10) {
                Button { withAnimation(.spring) { drawerOpen = true } } label: {
                    Image(systemName: "line.3.horizontal").font(.title3).foregroundColor(.primary)
                        .frame(width: 46, height: 46).background(Brand.surface(state.darkMode)).clipShape(Circle())
                        .shadow(radius: 4)
                }
                // ponytail: plain label for now; wire GMSAutocomplete here when Places SDK is added.
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    Text("Search places").foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14).frame(height: 46)
                .background(Brand.surface(state.darkMode)).clipShape(Capsule()).shadow(radius: 4)
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
            HStack(spacing: 8) {
                actionButton("mappin", "Pin") {
                    if let c = loc.location?.coordinate { state.saveLocation(c) }
                }
                actionButton("square.and.arrow.up", "Share") { nav = .groups }   // share flow lives under Groups for now
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
                userName: "", userTag: myTag, userPhoto: state.userPhoto(uid),
                tracking: $tracking,
                onNavigate: { dest in drawerOpen = false; nav = dest },
                onLogout: { drawerOpen = false; AuthService.signOut() }
            )
            .environmentObject(state)
            .transition(.move(edge: .leading))
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func destinationView(_ d: SidebarDestination) -> some View {
        switch d {
        case .friends:     FriendsView(myUid: uid, myTag: myTag)
        case .groups:      GroupsView(myUid: uid, myTag: myTag)
        case .messages:    GroupsView(myUid: uid, myTag: myTag)   // DMs deferred; Groups holds chat for now
        case .collections: CollectionsView()
        case .waypoints:   CollectionsView()
        case .settings:    SettingsView()
        case .profile:     ProfileView(uid: uid)
        }
    }
}

extension SidebarDestination: Identifiable { var id: Int { hashValue } }
