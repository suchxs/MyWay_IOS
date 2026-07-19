// Drives a 1:1 or group call end-to-end: Firestore signalling (Calls) + the LiveKit media connection.
// One shared instance, observed by CallOverlay to show the in-call / incoming UI from any screen.
// Audio + video; foreground only (no CallKit / background ringing — deliberately out of scope).
import Foundation
import LiveKit
import AVFoundation
import FirebaseFirestore

@MainActor
final class CallManager: ObservableObject {
    static let shared = CallManager()

    enum Phase { case idle, outgoing, incoming, connecting, active }
    @Published var phase: Phase = .idle
    @Published var peerTag = ""       // 1:1: other user's @tag. group: group name.
    @Published var peerPhoto = ""
    @Published var isGroup = false
    @Published var isVideo = false    // call is in video mode → overlay shows the video layout
    @Published var muted = false
    @Published var videoOn = false    // my camera is publishing
    @Published var speaker = false
    @Published private(set) var room: Room?   // published so the video view mounts once connected

    private var call: Call?                       // the current 1:1 call doc
    private var groupGid: String?                 // set while in a group call
    private var wantVideo = false                 // apply camera on connect
    private var callStartAt: Date?                // ring/join time — for "rang Xs" / "lasted X"
    private var wasActive = false                 // did a 1:1 call actually connect (peer picked up)?
    private var incomingReg: ListenerRegistration?
    private var callReg: ListenerRegistration?
    private var myUid = "", myTag = "", myPhoto = ""

    // Start watching for incoming calls once signed in (RootView calls this).
    func bind(uid: String, tag: String, photo: String) {
        myUid = uid; myTag = tag; myPhoto = photo
        incomingReg?.remove()
        incomingReg = Calls.listenIncoming(uid) { [weak self] call in
            guard let self else { return }
            if let call, call.from != uid, self.phase == .idle {
                self.call = call; self.peerTag = call.fromTag; self.peerPhoto = call.fromPhoto
                self.isVideo = call.video
                self.phase = .incoming
            } else if call == nil, self.phase == .incoming {
                self.reset()                       // caller canceled before I answered
            }
        }
    }

    func stop() {
        incomingReg?.remove(); incomingReg = nil
        if phase != .idle { hangUp() }
    }

    // ── Outgoing (1:1) ─────────────────────────────────────────────────────────────
    func startOutgoing(to uid: String, tag: String, photo: String, video: Bool) {
        guard phase == .idle, !myUid.isEmpty else { return }
        let id = PrivateMessages.pairId(myUid, uid)
        let c = Call(id: id, from: myUid, fromTag: myTag, fromPhoto: myPhoto, to: uid, toTag: tag, status: "ringing", video: video)
        call = c; peerTag = tag; peerPhoto = photo; isVideo = video; wantVideo = video
        callStartAt = Date(); wasActive = false; phase = .outgoing
        Calls.start(c)
        observeCall(id)
        connect(room: id)                          // caller joins the room right away and waits
    }

    // ── Incoming (1:1) ─────────────────────────────────────────────────────────────
    func accept() {
        guard let call, phase == .incoming else { return }
        Calls.accept(call.id)
        wantVideo = call.video
        phase = .connecting
        observeCall(call.id)
        connect(room: call.room)
    }

    func decline() { hangUp() }

    // ── Group ────────────────────────────────────────────────────────────────────
    // No ringing — you just join the group's shared room (name = gid).
    func startGroupCall(gid: String, name: String, photo: String, video: Bool) {
        guard phase == .idle, !myUid.isEmpty else { return }
        isGroup = true; groupGid = gid; peerTag = name; peerPhoto = photo
        isVideo = video; wantVideo = video; callStartAt = Date(); phase = .connecting
        let tag = myTag
        Calls.joinGroupCall(gid, groupName: name, uid: myUid) { wasFirst in
            Groups.postSystem(gid, text: wasFirst ? "📞 @\(tag) started a call" : "@\(tag) joined the call")
        }
        connect(room: gid)
    }

    // ── Shared ───────────────────────────────────────────────────────────────────
    func hangUp() {
        if isGroup, let gid = groupGid {
            let tag = myTag
            Calls.leaveGroupCall(gid, uid: myUid) { wasLast, sec in
                Groups.postSystem(gid, text: wasLast ? "📞 Call ended · lasted \(Self.durText(sec))"
                                                     : "@\(tag) left the call")
            }
        } else if let call { Calls.end(call.id) }   // 1:1: delete doc → peer's listener ends too
        let r = room
        Task { await r?.disconnect() }
        reset()
    }

    func toggleMute() {
        muted.toggle()
        let enabled = !muted
        Task { try? await room?.localParticipant.setMicrophone(enabled: enabled) }
    }

    func toggleVideo() {
        videoOn.toggle()
        if videoOn { isVideo = true }              // switch to video layout the moment the camera turns on
        let enabled = videoOn
        Task { try? await room?.localParticipant.setCamera(enabled: enabled) }
    }

    func flipCamera() {
        guard let pub = room?.localParticipant.videoTracks.first(where: { $0.source == .camera }),
              let capturer = (pub.track as? LocalVideoTrack)?.capturer as? CameraCapturer else { return }
        Task { try? await capturer.switchCameraPosition() }
    }

    // ponytail: LiveKit owns the AVAudioSession, so this is a best-effort route override — fine for a demo.
    func toggleSpeaker() {
        speaker.toggle()
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(speaker ? .speaker : .none)
    }

    // Watch the call doc: peer accepted (→ active) or hung up (doc deleted → nil).
    private func observeCall(_ id: String) {
        callReg?.remove()
        callReg = Calls.listen(id) { [weak self] call in
            guard let self else { return }
            if call == nil { self.reset() }                       // peer hung up / declined
            else if call?.status == "active", self.phase == .outgoing || self.phase == .connecting {
                self.phase = .active; self.wasActive = true       // peer picked up → not a missed call
            }
        }
    }

    private func connect(room name: String) {
        let wantVideo = self.wantVideo
        Calls.token(room: name) { [weak self] token, url in
            guard let self else { return }
            guard let token, let url else { self.hangUp(); return }
            Task {
                do {
                    let room = Room()
                    try await room.connect(url: url, token: token)
                    try await room.localParticipant.setMicrophone(enabled: true)
                    if wantVideo {
                        try await room.localParticipant.setCamera(enabled: true)
                        self.videoOn = true
                    }
                    self.room = room
                    if self.phase == .connecting { self.phase = .active }   // callee is live once connected
                } catch {
                    print("LiveKit connect failed:", error.localizedDescription)
                    self.hangUp()
                }
            }
        }
    }

    private func reset() {
        // Missed-call notice: I was the caller and the other side never picked up (never went active).
        if !isGroup, let call, call.from == myUid, !wasActive, let start = callStartAt {
            let sec = Int(Date().timeIntervalSince(start))
            PrivateMessages.postSystem(call.id, fromUid: myUid, fromTag: myTag, otherUid: call.to, otherTag: call.toTag,
                                       text: "📞 Missed call from @\(myTag) · rang \(Self.durText(sec))")
        }
        callReg?.remove(); callReg = nil
        room = nil; call = nil; groupGid = nil; callStartAt = nil; wasActive = false
        isGroup = false; isVideo = false; wantVideo = false
        muted = false; videoOn = false; speaker = false
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
        phase = .idle
    }

    static func durText(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m \(seconds % 60)s"
    }
}
