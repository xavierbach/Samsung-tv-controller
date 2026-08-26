import PhotosUI
import SwiftUI

struct ContentView: View {
    @AppStorage("serverURL") private var serverURLString = "http://192.168.1.57:8766"

    @StateObject private var speech = SpeechRecognizer()
    @Environment(\.scenePhase) private var scenePhase
    @State private var tvs: [TVStatus] = []
    @State private var reply: String = ""
    @State private var busy = false
    @State private var showSettings = false
    @State private var serverReachable = true
    @State private var artPickerItem: PhotosPickerItem?
    @State private var artCandidate: ArtworkImage?
    @State private var croppingArt = false
    @State private var connectionTest: String?
    @State private var testingConnection = false
    @State private var scanningTVs = false
    @State private var approvingTV: String?
    @State private var setupResult: String?

    private var client: ServerClient? {
        // Pasted addresses often carry an invisible trailing space/newline,
        // which is enough to make URL(string:) misparse the host.
        let trimmed = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: trimmed).map(ServerClient.init)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                background

                VStack(spacing: 0) {
                    header
                        .padding(.top, 8)

                    ScrollView {
                        roomGrid
                            .padding(.top, 18)
                    }
                    .scrollIndicators(.hidden)

                    conversationCard
                        .padding(.bottom, 22)

                    talkButton
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, 20)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { settings }
            .sheet(item: $artCandidate) { artwork in
                ArtworkSheet(artwork: artwork, tvs: tvs, client: client) { result in
                    reply = result
                }
                .presentationDetents([.large])
            }
        }
        .task {
            speech.requestPermissions()
            await refreshStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshStatus() } }
        }
        .onChange(of: artPickerItem) { _, item in
            guard let item else { return }
            Task { await prepareArtwork(from: item) }
        }
    }

    // MARK: chrome

    private var background: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.05, green: 0.05, blue: 0.09), location: 0),
                .init(color: Color(red: 0.09, green: 0.07, blue: 0.16), location: 0.55),
                .init(color: Color(red: 0.13, green: 0.08, blue: 0.22), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Home Cinema")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Text(headerSubtitle)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            PhotosPicker(selection: $artPickerItem, matching: .images) {
                Group {
                    if croppingArt {
                        ProgressView().tint(.white.opacity(0.7))
                    } else {
                        Image(systemName: "photo.artframe")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.08), in: Circle())
            }
            .disabled(croppingArt)
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.08), in: Circle())
            }
        }
    }

    private var headerSubtitle: String {
        if !serverReachable { return "Can't reach the house server" }
        if tvs.isEmpty { return "Looking for your TVs…" }
        let on = tvs.filter { $0.power == "on" }.count
        let art = tvs.filter { $0.power == "art" }.count
        var parts: [String] = []
        if on > 0 { parts.append("\(on) screen\(on == 1 ? "" : "s") on") }
        if art > 0 { parts.append("\(art) showing art") }
        return parts.isEmpty ? "All quiet" : parts.joined(separator: " · ")
    }

    // MARK: rooms

    private var roomGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            ForEach(tvs) { tv in
                RoomCard(tv: tv) {
                    Task { await send(quickToggleText(for: tv), spoken: false) }
                } onFullOff: {
                    Task { await send("turn the \(tv.name) tv fully off", spoken: false) }
                }
            }
        }
    }

    private func quickToggleText(for tv: TVStatus) -> String {
        // Art is the resting state, so a tap toggles between "showing
        // content" and "not": on → art, art/off → on. The real power-down
        // lives in the tile's long-press menu only.
        tv.power == "on" ? "turn off the \(tv.name) tv" : "turn on the \(tv.name) tv"
    }

    // MARK: conversation

    private var conversationCard: some View {
        Group {
            if speech.isListening {
                Text(speech.transcript.isEmpty ? "Listening…" : speech.transcript)
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundStyle(.white)
            } else if busy {
                HStack(spacing: 10) {
                    ProgressView().tint(.white.opacity(0.7))
                    Text("On it…")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else if !reply.isEmpty {
                Text(reply)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                Text("Hold the mic and say things like\n“movie night in the living room”")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 64)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: speech.transcript)
        .animation(.easeInOut(duration: 0.2), value: busy)
    }

    // MARK: mic

    private var micGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.55, green: 0.35, blue: 1.0), Color(red: 0.25, green: 0.65, blue: 1.0)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var talkButton: some View {
        ZStack {
            // level-reactive halo
            Circle()
                .fill(micGradient)
                .frame(width: 120, height: 120)
                .blur(radius: 32)
                .opacity(speech.isListening ? 0.55 + Double(speech.level) * 0.4 : 0.25)
                .scaleEffect(speech.isListening ? 1.15 + CGFloat(speech.level) * 0.6 : 1)
                .animation(.easeOut(duration: 0.12), value: speech.level)

            Circle()
                .fill(micGradient)
                .frame(width: 108, height: 108)
                .overlay(
                    Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1)
                )
                .overlay {
                    Image(systemName: speech.isListening ? "waveform" : "mic.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                .scaleEffect(speech.isListening ? 1.06 : 1)
                .shadow(color: Color(red: 0.4, green: 0.4, blue: 1.0).opacity(0.45), radius: 22, y: 8)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !speech.isListening && !busy { speech.start() }
                }
                .onEnded { _ in
                    let text = speech.stop()
                    guard !text.isEmpty else { return }
                    Task { await send(text) }
                }
        )
        .sensoryFeedback(.impact(weight: .medium), trigger: speech.isListening)
        .animation(.spring(duration: 0.25), value: speech.isListening)
    }

    // MARK: settings

    private var settings: some View {
        NavigationStack {
            Form {
                Section("Home server") {
                    TextField("http://192.168.1.57:8766", text: $serverURLString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        if testingConnection {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Testing…")
                            }
                        } else {
                            Text("Test connection")
                        }
                    }
                    .disabled(testingConnection)
                    if let connectionTest {
                        Text(connectionTest)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } footer: {
                    Text("Away from home the address must be the Mac's Tailscale "
                        + "IP or …ts.net name, and Tailscale must say Connected "
                        + "on this phone.")
                }
                Section {
                    Button {
                        Task { await scanForTVs() }
                    } label: {
                        if scanningTVs {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Scanning the network…")
                            }
                        } else {
                            Text("Scan for new TVs")
                        }
                    }
                    .disabled(scanningTVs || approvingTV != nil)
                    ForEach(samsungTVs) { tv in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(roomLabel(tv))
                                Text(tv.host)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if tv.authorized == true {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                            } else if approvingTV == tv.name {
                                ProgressView()
                            } else {
                                Button("Approve") {
                                    Task { await approve(tv) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(approvingTV != nil || scanningTVs)
                            }
                        }
                    }
                    if let setupResult {
                        Text(setupResult)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("TVs")
                } footer: {
                    Text("Approve pops the Allow prompt on that TV's screen — "
                        + "accept it with that TV's remote within 30 seconds. "
                        + "Once approved, access is saved on the server for good.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { showSettings = false } }
        }
        .presentationDetents([.medium, .large])
    }

    private var samsungTVs: [TVStatus] {
        tvs.filter { $0.host != "-" }  // Apple TV-only rooms need no approval
    }

    private func roomLabel(_ tv: TVStatus) -> String {
        tv.name
            .replacingOccurrences(of: "-frame", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func scanForTVs() async {
        guard let client else {
            setupResult = "Set the server address first."
            return
        }
        scanningTVs = true
        defer { scanningTVs = false }
        do {
            setupResult = try await client.discover().reply
            await refreshStatus()
        } catch {
            setupResult = "Scan failed — \(error.localizedDescription)"
        }
    }

    private func approve(_ tv: TVStatus) async {
        guard let client else { return }
        approvingTV = tv.name
        setupResult = "Watch the \(roomLabel(tv)) TV — accept the prompt with its remote…"
        defer { approvingTV = nil }
        do {
            setupResult = try await client.authorize(tv: tv.name).reply
            await refreshStatus()
        } catch {
            setupResult = "Approval failed — \(error.localizedDescription)"
        }
    }

    private func testConnection() async {
        guard let client else {
            connectionTest = "✗ That's not a valid URL — it should look like "
                + "http://100.106.18.20:8766 (no spaces)."
            return
        }
        testingConnection = true
        defer { testingConnection = false }
        do {
            if try await client.health() {
                connectionTest = "✓ The server is answering at \(client.baseURL.absoluteString)."
                serverReachable = true
                await refreshStatus()
            } else {
                connectionTest = "✗ Something answered there, but it isn't the TV "
                    + "server — double-check the address and port."
            }
        } catch let error as URLError {
            connectionTest = Self.explain(error, host: client.baseURL.host() ?? "the Mac")
        } catch {
            connectionTest = "✗ \(error.localizedDescription)"
        }
    }

    private static func explain(_ error: URLError, host: String) -> String {
        switch error.code {
        case .cannotConnectToHost:
            return "✗ Reached \(host), but nothing is listening on that port. "
                + "On the Mac, run: curl http://localhost:<port>/health — the "
                + "server is down, or running on a different port."
        case .timedOut:
            return "✗ No answer from \(host) at all. The Mac is asleep, or the "
                + "Tailscale tunnel isn't up — open Tailscale on this phone and "
                + "check the switch says Connected."
        case .cannotFindHost, .dnsLookupFailed:
            return "✗ Couldn't look up \(host). For a ….ts.net name, Tailscale "
                + "must be connected on this phone."
        case .notConnectedToInternet, .networkConnectionLost:
            return "✗ This phone has no network route to \(host) — check "
                + "Wi‑Fi/cellular, and that Tailscale says Connected."
        case .appTransportSecurityRequiresSecureConnection:
            return "✗ iOS blocked plain http to \(host). Regenerate the Xcode "
                + "project from the latest code (cd ios && xcodegen generate) "
                + "and rebuild — the fixed project allows it."
        default:
            return "✗ \(error.localizedDescription) (URLError \(error.code.rawValue))"
        }
    }

    // MARK: actions

    private func send(_ text: String, spoken: Bool = true) async {
        guard let client else {
            reply = "Set the server address in settings."
            return
        }
        busy = true
        defer { busy = false }
        do {
            let result = try await client.send(text)
            reply = result.reply
            serverReachable = true
        } catch let error as URLError where error.code == .timedOut {
            // The server is up but slow (busy with another command, or a long
            // agent turn) — reachability hasn't actually changed.
            reply = "The server is taking a while — try again in a moment."
        } catch is DecodingError {
            reply = "The server sent an unexpected reply — is it up to date?"
        } catch let error as URLError where error.code == .cannotConnectToHost {
            // The Mac answered the network but nothing accepted the port:
            // the server isn't running, or it's listening on a different port.
            reply = "Found the Mac, but no server answered on that port — "
                + "check the server is running and the port in Settings matches it."
            serverReachable = false
        } catch {
            reply = "Couldn't reach the house server — if you're away from home, "
                + "check Tailscale says Connected."
            serverReachable = false
        }
        await refreshStatus()
    }

    private func prepareArtwork(from item: PhotosPickerItem) async {
        croppingArt = true
        defer {
            croppingArt = false
            artPickerItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else {
            reply = "Couldn't read that photo — try another one."
            return
        }
        // Saliency + cropping a full-res photo is heavy; keep it off the UI.
        let artwork = await Task.detached(priority: .userInitiated) {
            SmartCropper.artwork(from: image)
        }.value
        guard let artwork else {
            reply = "Couldn't prepare that photo — try another one."
            return
        }
        await refreshStatus()  // fresh art_mode flags before we ask which TV
        artCandidate = artwork
    }

    private func refreshStatus() async {
        guard let client else { return }
        do {
            tvs = try await client.status()
            serverReachable = true
        } catch {
            serverReachable = false
        }
    }
}

// MARK: - Room card

struct RoomCard: View {
    let tv: TVStatus
    let onTap: () -> Void
    let onFullOff: () -> Void

    private var isOn: Bool { tv.power == "on" }
    private var isArt: Bool { tv.power == "art" }
    private var isAppleTVRoom: Bool { tv.power == "via apple tv" }

    private static let artAmber = Color(red: 0.95, green: 0.72, blue: 0.35)

    private var dotColor: Color {
        if isOn { return .green }
        if isArt { return Self.artAmber }
        if isAppleTVRoom { return .cyan.opacity(0.7) }
        return .white.opacity(0.2)
    }

    private var dotGlow: Color {
        if isOn { return .green.opacity(0.8) }
        if isArt { return Self.artAmber.opacity(0.7) }
        return .clear
    }

    private var roomName: String {
        tv.name
            .replacingOccurrences(of: "-frame", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private var subtitle: String {
        if isAppleTVRoom { return "Apple TV" }
        // A Samsung room with an Apple TV behind it: the tile is still the
        // Samsung, but advertise the precision layer.
        let state = isArt ? "Art" : (isOn ? "On" : "Off")
        return state + (tv.apple_tv ? " · Apple TV" : "")
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: isAppleTVRoom ? "appletv.fill" : (isArt ? "photo.artframe" : "tv"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isOn || isArt ? .white : .white.opacity(0.45))
                    Spacer()
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: dotGlow, radius: 4)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(roomName)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(isOn || isArt ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(isOn || isArt ? 0.18 : 0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if tv.power != "off" {
                Button(role: .destructive, action: onFullOff) {
                    Label("Turn fully off", systemImage: "power")
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
