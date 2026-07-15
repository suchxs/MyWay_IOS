// TripArrows.kt → SwiftUI. Edge-of-screen "guide" markers pointing at trip members who are currently
// off-screen: the member's avatar clamped to the screen edge with a chevron aimed at them. Tap to
// center on that member. Recomputes whenever the camera moves (via MapHolder.cameraTick).
import SwiftUI
import GoogleMaps
import CoreLocation

struct TripArrowsView: View {
    let members: [TripMember]
    let myUid: String
    @ObservedObject var holder: MapHolder
    var onTap: (CLLocationCoordinate2D) -> Void

    var body: some View {
        GeometryReader { geo in
            let items = offscreen(size: geo.size, tick: holder.cameraTick)
            ForEach(items, id: \.uid) { item in
                Button { onTap(item.coord) } label: {
                    ZStack {
                        AvatarCircle(photoBase64: item.photo, tag: item.tag, size: 34)
                            .overlay(Circle().stroke(Brand.teal, lineWidth: 2))
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(.system(size: 11)).foregroundColor(Brand.teal)
                            .offset(y: -24)
                            .rotationEffect(.radians(item.angle + .pi / 2))   // point the chevron at the member
                    }
                }
                .position(item.point)
            }
        }
    }

    private struct Arrow { let uid, tag, photo: String; let coord: CLLocationCoordinate2D; let point: CGPoint; let angle: Double }

    private func offscreen(size: CGSize, tick: Int) -> [Arrow] {
        _ = tick
        guard let proj = holder.map?.projection, size.width > 0 else { return [] }
        let margin: CGFloat = 44
        let left = margin, top = margin, right = size.width - margin, bottom = size.height - margin
        let cx = size.width / 2, cy = size.height / 2
        var out: [Arrow] = []
        for m in members where m.uid != myUid {
            guard let lat = m.lat, let lng = m.lng else { continue }
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            let p = proj.point(for: coord)
            if p.x >= 0, p.x <= size.width, p.y >= 0, p.y <= size.height { continue }   // on-screen → no arrow
            let edge = clamp(cx: cx, cy: cy, px: p.x, py: p.y, left: left, top: top, right: right, bottom: bottom)
            out.append(Arrow(uid: m.uid, tag: m.tag, photo: m.photo, coord: coord, point: edge,
                             angle: atan2(Double(p.y - cy), Double(p.x - cx))))
        }
        return out
    }

    // Where the ray centre→member crosses the inset screen rectangle (TripArrows.clampToRect).
    private func clamp(cx: CGFloat, cy: CGFloat, px: CGFloat, py: CGFloat,
                       left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) -> CGPoint {
        let dx = px - cx, dy = py - cy
        var t = CGFloat.greatestFiniteMagnitude
        if dx > 0 { t = min(t, (right - cx) / dx) } else if dx < 0 { t = min(t, (left - cx) / dx) }
        if dy > 0 { t = min(t, (bottom - cy) / dy) } else if dy < 0 { t = min(t, (top - cy) / dy) }
        if t == .greatestFiniteMagnitude { t = 0 }
        return CGPoint(x: cx + dx * t, y: cy + dy * t)
    }
}
