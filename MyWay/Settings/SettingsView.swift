// SettingsActivity.kt → SwiftUI. Marker appearance (pin colour, note icon, pencil icon) + dark mode +
// delete saved places. Marker settings are device-local (UserDefaults, via AppState).
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var hue = AppState.shared.pinHue
    @State private var pinIcon = AppState.shared.pinIcon
    @State private var pencilIcon = AppState.shared.pencilIcon
    @State private var confirmClear = false

    private let hues: [Double] = [0, 30, 60, 120, 210, 240, 270, 330]
    private let pinIcons = ["📝", "📍", "⭐", "❤️", "🔖", "🚩"]
    private let pencilIcons = ["✏️", "🖊️", "📌", "⭐", "❗", "🎯"]

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Dark mode", isOn: $state.darkMode).tint(Brand.teal)
            }

            Section("Pin colour") {
                HStack(spacing: 12) {
                    ForEach(hues, id: \.self) { h in
                        Circle().fill(Color(hue: h / 360, saturation: 0.85, brightness: 0.9))
                            .frame(width: 34, height: 34)
                            .overlay(Circle().stroke(Color.primary, lineWidth: h == hue ? 3 : 0))
                            .onTapGesture { hue = h; state.pinHue = h }
                    }
                }.padding(.vertical, 4)
            }

            Section("Pin note icon") {
                iconPicker(pinIcons, selected: pinIcon) { pinIcon = $0; state.pinIcon = $0 }
            }

            Section("Pencil icon (zoomed-out note)") {
                iconPicker(pencilIcons, selected: pencilIcon) { pencilIcon = $0; state.pencilIcon = $0 }
            }

            Section {
                Button("🗑️  Delete my saved places", role: .destructive) { confirmClear = true }
            } footer: {
                Text("Removes every saved pin, note and collection from your account, on all devices. Your account isn't affected.")
            }
        }
        .navigationTitle("Settings")
        .alert("Delete my saved places?", isPresented: $confirmClear) {
            Button("Delete", role: .destructive) { state.clearMyPlaces(); state.clearAllCollections() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes all saved pins, notes and collections from your account, on every device. This can't be undone.")
        }
    }

    private func iconPicker(_ icons: [String], selected: String, onPick: @escaping (String) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(icons, id: \.self) { icon in
                Text(icon).font(.title2)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 12).fill(icon == selected ? Brand.teal.opacity(0.20) : Color.gray.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.tealDeep, lineWidth: icon == selected ? 2 : 0))
                    .onTapGesture { onPick(icon) }
            }
        }.padding(.vertical, 4)
    }
}
