// GMSMapView wrapped for SwiftUI. Ports MapMarkers.kt + TripLayer.kt behavior:
//  • personal pins (coloured by hue) with floating note cards that collapse to a pencil below zoom 12
//  • during a trip, personal pins are hidden; trip members render as avatar markers and shared trip
//    pins render as red pins + a card showing the creator's @tag
//  • Pin mode drops a green temp marker where you tap
import SwiftUI
import GoogleMaps

struct GoogleMapView: UIViewRepresentable {
    var places: [SavedPlace]
    var pinHue: Double
    var pinIcon: String
    var pencilGlyph: String
    var dark: Bool
    var showPersonal: Bool                 // false while on a trip (personal pins hidden)
    var members: [TripMember] = []
    var liveShares: [TripMember] = []      // people sharing their live location with me (avatar markers)
    var tripPins: [TripPin] = []
    var dest: TripDest? = nil
    var routePoints: [CLLocationCoordinate2D] = []
    var tempPin: CLLocationCoordinate2D? = nil
    var myUid: String = ""
    var holder: MapHolder? = nil
    var navFollow: GMSCameraPosition? = nil
    @Binding var camera: GMSCameraPosition?
    var onTapMarker: (SavedPlace) -> Void
    var onLongPress: (CLLocationCoordinate2D) -> Void
    var onTapPOI: ((String, String, CLLocationCoordinate2D) -> Void)? = nil
    var onTap: ((CLLocationCoordinate2D) -> Void)? = nil
    var onTapTripPin: ((TripPin) -> Void)? = nil
    var onUserPan: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> GMSMapView {
        let view = GMSMapView()
        view.delegate = context.coordinator
        view.isMyLocationEnabled = true
        view.settings.myLocationButton = false   // we draw our own My Location button (see MapHomeView)
        holder?.map = view
        applyStyle(view)
        return view
    }

    func updateUIView(_ view: GMSMapView, context: Context) {
        applyStyle(view)
        holder?.map = view
        // While navigating, inset the top so the camera target (you) sits lower on screen — more road
        // ahead is visible, like Google Maps' driver view.
        view.padding = navFollow != nil ? UIEdgeInsets(top: 240, left: 0, bottom: 0, right: 0) : .zero
        // Continuous nav follow (position + heading + tilt) takes priority over one-shot centering.
        if let navFollow {
            let key = "\(navFollow.target.latitude),\(navFollow.target.longitude),\(navFollow.bearing),\(navFollow.viewingAngle)"
            if context.coordinator.lastNavKey != key {
                context.coordinator.lastNavKey = key
                CATransaction.begin()
                CATransaction.setValue(NSNumber(value: 0.9), forKey: kCATransactionAnimationDuration)
                view.animate(to: navFollow)
                CATransaction.commit()
            }
        } else if let camera {
            let key = "\(camera.target.latitude),\(camera.target.longitude),\(camera.zoom)"
            if context.coordinator.lastCameraKey != key {
                context.coordinator.lastCameraKey = key
                view.animate(to: camera)
            }
        }

        let sig = signature()
        guard context.coordinator.lastSignature != sig else { return }
        context.coordinator.lastSignature = sig
        context.coordinator.rebuild(on: view, parent: self)
    }

    private func signature() -> String {
        let placeSig = showPersonal ? places.map { "\($0.key)\($0.name)\($0.note)" }.joined() : ""
        let memberSig = (members + liveShares).map { "\($0.uid)\($0.lat ?? 0)\($0.lng ?? 0)" }.joined()
        let pinSig = tripPins.map { "\($0.id)\($0.name)\($0.note)" }.joined()
        let destSig = dest.map { "\($0.lat)\($0.lng)" } ?? ""
        let routeSig = "\(routePoints.count)\(routePoints.first?.latitude ?? 0)"
        let tempSig = tempPin.map { "\($0.latitude)\($0.longitude)" } ?? ""
        return "\(placeSig)|\(pinHue)|\(pinIcon)|\(pencilGlyph)|\(dark)|\(showPersonal)|\(memberSig)|\(pinSig)|\(destSig)|\(routeSig)|\(tempSig)"
    }

    private func applyStyle(_ view: GMSMapView) {
        view.mapStyle = dark ? try? GMSMapStyle(jsonString: MapStyle.darkJSON) : nil
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GoogleMapView
        var lastSignature = ""
        var lastCameraKey = ""
        var lastNavKey = ""
        private var labels: [(marker: GMSMarker, full: UIImage)] = []
        private var collapsed: Bool?
        private var pencilImg = UIImage()
        init(_ parent: GoogleMapView) { self.parent = parent }

        func rebuild(on view: GMSMapView, parent: GoogleMapView) {
            self.parent = parent
            view.clear()
            labels = []
            collapsed = nil
            pencilImg = MarkerImages.pencil(glyph: parent.pencilGlyph, dark: parent.dark)

            // Route polyline
            if parent.routePoints.count > 1 {
                let path = GMSMutablePath()
                parent.routePoints.forEach { path.add($0) }
                let line = GMSPolyline(path: path)
                line.strokeWidth = 6
                line.strokeColor = UIColor(red: 0, green: 0.65, blue: 0.49, alpha: 1)
                line.map = view
            }

            if parent.showPersonal {
                let color = UIColor(hue: CGFloat(parent.pinHue / 360), saturation: 0.85, brightness: 0.9, alpha: 1)
                for place in parent.places {
                    let title = place.name.isEmpty ? String(format: "%.5f, %.5f", place.lat, place.lng) : place.name
                    if !place.isLandmark {
                        let m = GMSMarker(position: place.coordinate)
                        m.icon = GMSMarker.markerImage(with: color)
                        m.userData = "place:\(place.key)"
                        m.map = view
                    }
                    if !place.note.isEmpty {
                        addLabel(on: view, at: place.coordinate, title: place.isLandmark ? "" : title,
                                 note: place.note, tag: "place:\(place.key)")
                    }
                }
            } else {
                // Trip overlay
                for m in parent.members where m.uid != parent.myUid {
                    guard let lat = m.lat, let lng = m.lng else { continue }
                    let marker = GMSMarker(position: CLLocationCoordinate2D(latitude: lat, longitude: lng))
                    marker.icon = MarkerImages.avatar(photoBase64: m.photo, tag: m.tag)
                    marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
                    marker.zIndex = 6
                    marker.title = "@\(m.tag)"
                    marker.map = view
                }
                for p in parent.tripPins {
                    let name = p.name.isEmpty ? "Shared pin" : p.name
                    let marker = GMSMarker(position: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng))
                    // The creator's profile picture IS the pin, so you can see who dropped it.
                    marker.icon = MarkerImages.avatar(photoBase64: p.fromPhoto, tag: p.fromTag)
                    marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
                    marker.userData = "trippin:\(p.id)"
                    marker.zIndex = 3
                    marker.map = view
                    addLabel(on: view, at: marker.position, title: "\(name)  ·  @\(p.fromTag)", note: p.note, tag: "trippin:\(p.id)")
                }
            }

            // Live-location shares (from DMs) — always shown, avatar markers, regardless of trip state.
            for s in parent.liveShares where s.uid != parent.myUid {
                guard let lat = s.lat, let lng = s.lng else { continue }
                let marker = GMSMarker(position: CLLocationCoordinate2D(latitude: lat, longitude: lng))
                marker.icon = MarkerImages.avatar(photoBase64: s.photo, tag: s.tag)
                marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
                marker.zIndex = 7
                marker.title = "@\(s.tag) · live"
                marker.map = view
            }

            if let dest = parent.dest {
                let marker = GMSMarker(position: CLLocationCoordinate2D(latitude: dest.lat, longitude: dest.lng))
                marker.icon = GMSMarker.markerImage(with: .systemGreen)
                marker.title = dest.name.isEmpty ? "Destination" : dest.name
                marker.map = view
            }
            if let temp = parent.tempPin {
                let marker = GMSMarker(position: temp)
                marker.icon = GMSMarker.markerImage(with: .systemGreen)
                marker.map = view
            }
            applyZoom(view.camera.zoom)
        }

        private func addLabel(on view: GMSMapView, at pos: CLLocationCoordinate2D, title: String, note: String, tag: String) {
            let full = MarkerImages.noteCard(title: title, note: note, noteIcon: parent.pinIcon, dark: parent.dark)
            let marker = GMSMarker(position: CLLocationCoordinate2D(latitude: pos.latitude + 0.00018, longitude: pos.longitude))
            marker.icon = full
            marker.groundAnchor = CGPoint(x: 0.5, y: 1.0)
            marker.zIndex = 2
            marker.userData = tag
            marker.map = view
            labels.append((marker, full))
        }

        // Collapse note cards to a pencil below zoom 12 (MapMarkers.applyZoom).
        private func applyZoom(_ zoom: Float) {
            guard !labels.isEmpty else { return }
            let collapse = zoom < MarkerImages.labelZoom
            if collapsed == collapse { return }
            collapsed = collapse
            for (marker, full) in labels { marker.icon = collapse ? pencilImg : full }
        }

        func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) {
            applyZoom(position.zoom)
            if let holder = parent.holder { Task { @MainActor in holder.bearing = position.bearing; holder.cameraTick &+= 1 } }
        }

        // Any gesture (pan/rotate/zoom) means the user took over → stop the nav follow until they recenter.
        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            if gesture { parent.onUserPan?() }
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            guard let tag = marker.userData as? String else { return false }
            if tag.hasPrefix("place:") {
                let key = String(tag.dropFirst(6))
                if let place = parent.places.first(where: { $0.key == key }) { parent.onTapMarker(place); return true }
            } else if tag.hasPrefix("trippin:") {
                let id = String(tag.dropFirst(8))
                if let pin = parent.tripPins.first(where: { $0.id == id }) { parent.onTapTripPin?(pin); return true }
            }
            return false
        }

        func mapView(_ mapView: GMSMapView, didLongPressAt coordinate: CLLocationCoordinate2D) {
            parent.onLongPress(coordinate)
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            parent.onTap?(coordinate)
        }

        func mapView(_ mapView: GMSMapView, didTapPOIWithPlaceID placeID: String, name: String, location: CLLocationCoordinate2D) {
            parent.onTapPOI?(placeID, name, location)
        }
    }
}
