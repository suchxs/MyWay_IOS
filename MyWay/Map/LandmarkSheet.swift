// PlaceSheets.kt (landmark detail) → SwiftUI. Google Places details screen matching the Android layout:
// a photo gallery (tap → fullscreen), rating → reviews, price + open/closed chips, a details card
// (address / hours / phone / website), and a reviews list. Uses the current Places SDK request API.
import SwiftUI
import GooglePlaces
import CoreLocation

struct OpenStatus: Equatable { let text: String; let open: Bool }

@MainActor
final class LandmarkLoader: ObservableObject {
    @Published var name = ""
    @Published var address = ""
    @Published var rating: Float = 0
    @Published var ratingsTotal = 0
    @Published var priceLevel = 0            // 0 = none, 1–4 = $–$$$$
    @Published var weekdayText: [String] = []
    @Published var phone = ""
    @Published var website: URL?
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var photos: [UIImage] = []
    @Published var reviews: [GMSPlaceReview] = []
    @Published var openStatus: OpenStatus?
    @Published var loading = true

    private var loaded = false

    func load(placeID: String) {
        guard !loaded else { return }; loaded = true
        // Details + photos via the classic field API — it reliably populates place.photos (the newer
        // property API returned nil photos). Reviews aren't on GMSPlaceField, so fetch those separately.
        let fields: GMSPlaceField = [.name, .formattedAddress, .rating, .userRatingsTotal, .priceLevel,
                                     .openingHours, .phoneNumber, .website, .photos, .coordinate, .businessStatus]
        GMSPlacesClient.shared().fetchPlace(fromPlaceID: placeID, placeFields: fields, sessionToken: nil) { [weak self] place, _ in
            guard let self, let place else { self?.loading = false; return }
            self.name = place.name ?? ""
            self.address = place.formattedAddress ?? ""
            self.rating = place.rating
            self.ratingsTotal = Int(place.userRatingsTotal)
            self.priceLevel = self.priceDollars(place.priceLevel)
            self.weekdayText = place.openingHours?.weekdayText ?? []
            self.phone = place.phoneNumber ?? ""
            self.website = place.website
            self.coordinate = place.coordinate
            self.loading = false
            self.resolveOpen(place: place, placeID: placeID)
            for meta in (place.photos ?? []).prefix(8) {
                GMSPlacesClient.shared().loadPlacePhoto(meta) { img, _ in
                    guard let img else { return }
                    DispatchQueue.main.async { self.photos.append(img) }
                }
            }
        }
        // Reviews via the property API (not available on GMSPlaceField).
        let reviewReq = GMSFetchPlaceRequest(placeID: placeID, placeProperties: [GMSPlaceProperty.reviews.rawValue], sessionToken: nil)
        GMSPlacesClient.shared().fetchPlace(with: reviewReq) { [weak self] place, _ in
            self?.reviews = place?.reviews ?? []
        }
    }

    private func priceDollars(_ level: GMSPlacesPriceLevel) -> Int {
        switch level {
        case .cheap: return 1
        case .medium: return 2
        case .high: return 3
        case .expensive: return 4
        default: return 0
        }
    }

    private func resolveOpen(place: GMSPlace, placeID: String) {
        switch place.businessStatus {
        case .closedPermanently: openStatus = OpenStatus(text: "Permanently closed", open: false); return
        case .closedTemporarily: openStatus = OpenStatus(text: "Temporarily closed", open: false); return
        default: break
        }
        GMSPlacesClient.shared().isOpen(withPlaceID: placeID) { [weak self] status, _ in
            switch status {
            case .open: self?.openStatus = OpenStatus(text: "Open now", open: true)
            case .closed: self?.openStatus = OpenStatus(text: "Closed", open: false)
            default: break
            }
        }
    }
}

struct LandmarkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var state: AppState
    @StateObject private var loader = LandmarkLoader()
    let placeID: String
    let fallbackName: String
    let coordinate: CLLocationCoordinate2D
    var myUid: String = ""
    var myTag: String = ""
    var onDirections: (CLLocationCoordinate2D, String) -> Void

    @State private var viewerIndex: Indexed?
    @State private var showReviews = false
    @State private var note = ""
    @State private var showShare = false

    private var title: String { loader.name.isEmpty ? fallbackName : loader.name }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    gallery
                    Text(title).font(.title2).bold()
                    chips
                    actions
                    noteAndShare
                    detailsCard
                    if !loader.reviews.isEmpty {
                        Button { showReviews = true } label: {
                            Label("Reviews (\(loader.reviews.count))", systemImage: "star.bubble")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered).tint(Brand.teal)
                    }
                    if loader.loading { ProgressView().frame(maxWidth: .infinity) }
                }.padding(16)
            }
            .navigationTitle("Landmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear {
                loader.load(placeID: placeID)
                if let saved = state.places.first(where: { $0.placeId == placeID }) { note = saved.note }
            }
            .sheet(isPresented: $showReviews) { ReviewsSheet(reviews: loader.reviews) }
            .sheet(isPresented: $showShare) {
                GroupPickerSheet(myUid: myUid) { group in
                    let c = loader.coordinate ?? coordinate
                    Groups.sharePin(group.id, fromUid: myUid, fromTag: myTag, lat: c.latitude, lng: c.longitude,
                                    name: title, note: note, placeId: placeID)
                    showShare = false
                }
            }
            .fullScreenCover(item: $viewerIndex) { idx in
                PhotoViewer(images: loader.photos, start: idx.value, onClose: { viewerIndex = nil })
            }
        }
    }

    // ── Gallery ──────────────────────────────────────────────────────────────────
    @ViewBuilder private var gallery: some View {
        if !loader.photos.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(loader.photos.enumerated()), id: \.offset) { i, img in
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 240, height: 160).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .onTapGesture { viewerIndex = Indexed(value: i) }  // open fullscreen
                    }
                }
            }
        }
    }

    // ── Chips: rating → reviews, price, open/closed ───────────────────────────────
    private var chips: some View {
        HStack(spacing: 8) {
            if loader.rating > 0 {
                Button { if !loader.reviews.isEmpty { showReviews = true } } label: {
                    HStack(spacing: 4) {
                        Text("★").foregroundColor(Color(hex: 0xF59E0B))
                        Text(String(format: "%.1f", loader.rating)).bold()
                        if loader.ratingsTotal > 0 { Text("· \(compactCount(loader.ratingsTotal))").foregroundColor(.secondary) }
                    }.font(.footnote)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color(hex: 0xF59E0B).opacity(0.15)).clipShape(Capsule())
                }.tint(.primary)
            }
            if loader.priceLevel > 0 {
                Text(String(repeating: "$", count: loader.priceLevel)).font(.footnote).bold()
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.gray.opacity(0.15)).clipShape(Capsule())
            }
            if let s = loader.openStatus {
                let c = s.open ? Color(hex: 0x16A34A) : Color(hex: 0xEF4444)
                HStack(spacing: 4) { Text("●").font(.system(size: 8)); Text(s.text).bold() }
                    .font(.footnote).foregroundColor(c)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(c.opacity(0.14)).clipShape(Capsule())
            }
            Spacer()
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { onDirections(loader.coordinate ?? coordinate, title); dismiss() } label: {
                Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(Brand.teal)
            Button {
                let c = loader.coordinate ?? coordinate
                state.saveLocation(c)
                let key = locationKey(c.latitude, c.longitude)
                state.saveName(key, title)
                Places.setPlaceField(AuthService.currentUid ?? "", key: key, field: "placeId", value: placeID)
                dismiss()
            } label: { Label("Save", systemImage: "bookmark.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).tint(Brand.teal)
        }
    }

    // Note + share to a group (MarkerActionsSheet parity). Adding a note saves the landmark to your map.
    private var noteAndShare: some View {
        VStack(spacing: 10) {
            HStack {
                TextField("Add a note…", text: $note, axis: .vertical).lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                Button("Save") { saveNote() }.buttonStyle(.borderedProminent).tint(Brand.teal)
                    .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Button { showShare = true } label: {
                Label("Share to a group", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).tint(Brand.tealDeep)
        }
    }

    private func saveNote() {
        let c = loader.coordinate ?? coordinate
        state.saveLocation(c)
        let key = locationKey(c.latitude, c.longitude)
        state.saveName(key, title)
        Places.setPlaceField(myUid, key: key, field: "placeId", value: placeID)
        state.saveNote(key, note)
    }

    @ViewBuilder private var detailsCard: some View {
        VStack(spacing: 0) {
            if !loader.address.isEmpty { infoRow("📍", loader.address) }
            if !loader.weekdayText.isEmpty { Divider(); infoRow("🕐", loader.weekdayText.joined(separator: "\n")) }
            if !loader.phone.isEmpty {
                Divider()
                if let tel = URL(string: "tel:\(loader.phone.filter { !$0.isWhitespace })") {
                    Link(destination: tel) { infoRow("📞", loader.phone, tint: Brand.tealDeep) }
                }
            }
            if let site = loader.website { Divider(); Link(destination: site) { infoRow("🌐", site.absoluteString, tint: Brand.tealDeep) } }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.gray.opacity(0.08)))
    }

    private func infoRow(_ emoji: String, _ text: String, tint: Color? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji)
            Text(text).font(.subheadline).foregroundColor(tint ?? .primary).multilineTextAlignment(.leading)
            Spacer()
        }.padding(12)
    }

    private func compactCount(_ n: Int) -> String {
        n < 1000 ? "\(n) reviews" : String(format: "%.1fk reviews", Double(n) / 1000)
    }
}

// fullScreenCover(item:) needs an Identifiable; wrap the index.
private struct Indexed: Identifiable { let value: Int; var id: Int { value } }

private struct PhotoViewer: View {
    let images: [UIImage]
    let start: Int
    var onClose: () -> Void
    @State private var page = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $page) {
                ForEach(Array(images.enumerated()), id: \.offset) { i, img in
                    Image(uiImage: img).resizable().scaledToFit().tag(i)
                }
            }.tabViewStyle(.page)
            Button { onClose() } label: {
                Image(systemName: "xmark").foregroundColor(.white).padding(12)
                    .background(Color.black.opacity(0.5)).clipShape(Circle())
            }.padding()
        }
        .onAppear { page = start }
    }
}

private struct ReviewsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let reviews: [GMSPlaceReview]

    var body: some View {
        NavigationStack {
            List(Array(reviews.enumerated()), id: \.offset) { _, r in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        let author = r.authorAttribution?.name ?? "Anonymous"
                        AvatarCircle(photoBase64: "", tag: author, size: 34)
                        VStack(alignment: .leading) {
                            Text(author).font(.subheadline).bold()
                            if let t = r.relativePublishDateDescription { Text(t).font(.caption2).foregroundColor(.secondary) }
                        }
                        Spacer()
                        Text("★ \(String(format: "%.0f", r.rating))").font(.caption).bold()
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color(hex: 0xF59E0B).opacity(0.15)).clipShape(Capsule())
                    }
                    if let text = r.text, !text.isEmpty { Text(text).font(.subheadline).foregroundColor(.secondary) }
                }.padding(.vertical, 4)
            }
            .navigationTitle("Reviews")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
