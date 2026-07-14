// Sidebar.kt → SwiftUI slide-in drawer: profile header + PLACES / SOCIAL / SETTINGS nav.
import SwiftUI

enum SidebarDestination { case waypoints, collections, messages, friends, groups, settings, profile }

struct Sidebar: View {
    @EnvironmentObject var state: AppState
    let userName: String
    let userTag: String
    let userPhoto: String
    @Binding var tracking: Bool
    let onNavigate: (SidebarDestination) -> Void
    let onLogout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "map.circle.fill").resizable().frame(width: 44, height: 44).foregroundColor(Brand.teal)
                VStack(alignment: .leading) {
                    Text("MyWay").font(.title2).bold()
                    Text("Group travel companion").font(.caption).foregroundColor(.secondary)
                }
            }.padding(.bottom, 8)

            Button { onNavigate(.profile) } label: {
                VStack(spacing: 0) {
                    LinearGradient(colors: [Brand.tealBright, Brand.tealDeep], startPoint: .leading, endPoint: .trailing)
                        .frame(height: 56)
                    HStack {
                        AvatarCircle(photoBase64: userPhoto, tag: userTag.isEmpty ? "?" : userTag, size: 44)
                        VStack(alignment: .leading) {
                            Text(userName.isEmpty ? "Set up your profile" : userName).bold().lineLimit(1)
                            if !userTag.isEmpty { Text("@\(userTag)").font(.caption).foregroundColor(.secondary) }
                        }
                        Spacer()
                    }.padding(10)
                }
                .background(Brand.teal.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    section("PLACES")
                    item("mappin.and.ellipse", "Waypoints") { onNavigate(.waypoints) }
                    item("folder", "Collections") { onNavigate(.collections) }
                    section("SOCIAL")
                    item("bubble.left.and.bubble.right", "Messages") { onNavigate(.messages) }
                    item("person.2", "Friends") { onNavigate(.friends) }
                    item("safari", "Groups") { onNavigate(.groups) }
                    section("SETTINGS")
                    item("gearshape", "Settings") { onNavigate(.settings) }
                    HStack {
                        iconBadge("dot.radiowaves.left.and.right", Brand.teal)
                        Text("Tracking").fontWeight(.medium)
                        Spacer()
                        Toggle("", isOn: $tracking).labelsHidden().tint(Brand.teal)
                    }.padding(.vertical, 4).padding(.horizontal, 6)
                    item(state.darkMode ? "sun.max" : "moon", state.darkMode ? "Light Mode" : "Dark Mode") {
                        state.darkMode.toggle()
                    }
                }
            }
            Spacer()
            item("rectangle.portrait.and.arrow.right", "Log out", danger: true, action: onLogout)
        }
        .padding(16)
        .frame(width: 288)
        .frame(maxHeight: .infinity)
        .background(Brand.surface(state.darkMode))
    }

    private func section(_ t: String) -> some View {
        Text(t).font(.caption2).bold().foregroundColor(.secondary.opacity(0.7))
            .padding(.leading, 8).padding(.top, 8).padding(.bottom, 4)
    }

    private func iconBadge(_ sys: String, _ color: Color) -> some View {
        ZStack { Circle().fill(color.opacity(0.12)); Image(systemName: sys).foregroundColor(color) }
            .frame(width: 38, height: 38)
    }

    private func item(_ sys: String, _ label: String, danger: Bool = false, action: @escaping () -> Void) -> some View {
        let accent: Color = danger ? Color(hex: 0xEF4444) : Brand.teal
        return Button(action: action) {
            HStack {
                iconBadge(sys, accent)
                Text(label).fontWeight(.medium).foregroundColor(danger ? accent : .primary)
                Spacer()
            }.padding(.vertical, 8).padding(.horizontal, 6)
        }.buttonStyle(.plain)
    }
}
