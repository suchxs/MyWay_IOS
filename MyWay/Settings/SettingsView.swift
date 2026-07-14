// SettingsActivity.kt → SwiftUI. Dark mode, pin color, clear local map data.
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var hue: Double = AppState.shared.pinHue
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Dark mode", isOn: $state.darkMode).tint(Brand.teal)
            }
            Section("Pin colour") {
                Slider(value: $hue, in: 0...330, step: 30) { _ in state.pinHue = hue }
                HStack {
                    Circle().fill(Color(hue: hue / 360, saturation: 0.75, brightness: 0.9)).frame(width: 28, height: 28)
                    Text("Hue \(Int(hue))")
                }
            }
            Section {
                Button("Delete my saved places", role: .destructive) { confirmClear = true }
            } footer: {
                Text("Removes every pin, note and collection from this account — on all your devices.")
            }
        }
        .navigationTitle("Settings")
        .alert("Delete all saved places?", isPresented: $confirmClear) {
            Button("Delete", role: .destructive) { state.clearMyPlaces() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
