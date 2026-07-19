// Full-screen call UI, mounted once at the root so it can appear over any screen. Handles the incoming
// ring (accept/decline) and the in-call controls (mute / video / flip / speaker / hang up), plus the
// video layout (remote participants in a grid + a local self-view PiP) when the call is in video mode.
import SwiftUI
import LiveKit

struct CallOverlay: View {
    @ObservedObject private var cm = CallManager.shared

    var body: some View {
        if cm.phase != .idle {
            ZStack {
                if cm.isVideo, let room = cm.room {
                    CallVideoView(room: room).ignoresSafeArea()
                    LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.55)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                } else {
                    LinearGradient(colors: [Brand.tealDeep, .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                }
                VStack(spacing: 16) {
                    Spacer()
                    if !cm.isVideo || cm.room == nil {
                        AvatarCircle(photoBase64: cm.peerPhoto, tag: cm.peerTag, size: 120)
                        Text(cm.isGroup ? cm.peerTag : "@\(cm.peerTag)").font(.title).bold().foregroundColor(.white)
                    }
                    Text(statusText).font(.headline).foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(cm.isVideo ? AnyView(Capsule().fill(.black.opacity(0.4))) : AnyView(Color.clear))
                    Spacer()
                    controls
                    Spacer().frame(height: 24)
                }
                .padding()
            }
        }
    }

    private var statusText: String {
        switch cm.phase {
        case .incoming:   return cm.isVideo ? "Incoming video call…" : "Incoming call…"
        case .outgoing:   return "Calling…"
        case .connecting: return "Connecting…"
        case .active:     return cm.isGroup ? cm.peerTag : "Connected"
        case .idle:       return ""
        }
    }

    @ViewBuilder private var controls: some View {
        if cm.phase == .incoming {
            HStack(spacing: 64) {
                circleButton("phone.down.fill", bg: .red, fg: .white, "Decline") { cm.decline() }
                circleButton("phone.fill", bg: .green, fg: .white, "Accept") { cm.accept() }
            }
        } else {
            HStack(spacing: 24) {
                circleButton(cm.muted ? "mic.slash.fill" : "mic.fill",
                             bg: cm.muted ? .white : .white.opacity(0.25),
                             fg: cm.muted ? Brand.tealDeep : .white, "Mute", small: true) { cm.toggleMute() }
                circleButton(cm.videoOn ? "video.fill" : "video.slash.fill",
                             bg: cm.videoOn ? .white : .white.opacity(0.25),
                             fg: cm.videoOn ? Brand.tealDeep : .white, "Video", small: true) { cm.toggleVideo() }
                circleButton("phone.down.fill", bg: .red, fg: .white, "End") { cm.hangUp() }
                if cm.videoOn {
                    circleButton("arrow.triangle.2.circlepath.camera.fill",
                                 bg: .white.opacity(0.25), fg: .white, "Flip", small: true) { cm.flipCamera() }
                } else {
                    circleButton(cm.speaker ? "speaker.wave.2.fill" : "speaker.fill",
                                 bg: cm.speaker ? .white : .white.opacity(0.25),
                                 fg: cm.speaker ? Brand.tealDeep : .white, "Speaker", small: true) { cm.toggleSpeaker() }
                }
            }
        }
    }

    private func circleButton(_ icon: String, bg: Color, fg: Color, _ label: String, small: Bool = false,
                              action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: small ? 22 : 28))
                    .foregroundColor(fg)
                    .frame(width: small ? 58 : 72, height: small ? 58 : 72)
                    .background(Circle().fill(bg))
            }
            Text(label).font(.caption).foregroundColor(.white.opacity(0.85))
        }
    }
}

// Remote participants' camera feeds in an adaptive grid, with my own camera as a small PiP in the corner.
private struct CallVideoView: View {
    @ObservedObject var room: Room

    private var remoteIds: [Participant.Identity] { Array(room.remoteParticipants.keys) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
            if remoteIds.isEmpty {
                Text("Waiting for others…").foregroundColor(.white.opacity(0.7))
            } else {
                let cols = remoteIds.count <= 1 ? 1 : 2
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: cols), spacing: 2) {
                    ForEach(remoteIds, id: \.self) { id in
                        if let p = room.remoteParticipants[id] {
                            ParticipantTile(participant: p).aspectRatio(3/4, contentMode: .fit)
                        }
                    }
                }
            }
            // My self-view.
            ParticipantTile(participant: room.localParticipant)
                .frame(width: 108, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.5), lineWidth: 1))
                .padding(.top, 60).padding(.trailing, 12)
        }
    }
}

// One participant's video (or their avatar when the camera is off).
private struct ParticipantTile: View {
    @ObservedObject var participant: Participant

    private var cameraTrack: VideoTrack? {
        participant.videoTracks.first { $0.source == .camera }?.track as? VideoTrack
    }

    var body: some View {
        ZStack {
            Color(white: 0.12)
            if participant.isCameraEnabled(), let track = cameraTrack {
                SwiftUIVideoView(track)
            } else {
                AvatarCircle(photoBase64: "", tag: String(participant.identity?.stringValue ?? "?"), size: 64)
            }
        }
    }
}
