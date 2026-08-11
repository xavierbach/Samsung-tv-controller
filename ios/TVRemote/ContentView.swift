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

    private var client: ServerClient? {
        URL(string: serverURLString).map(ServerClient.init)
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
        }
        .task {
            speech.requestPermissions()
            await refreshStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshStatus() } }
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
        return on == 0 ? "All quiet" : "\(on) screen\(on == 1 ? "" : "s") on"
    }

    // MARK: rooms

    private var roomGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            ForEach(tvs) { tv in
                RoomCard(tv: tv) {
                    Task { await send(quickToggleText(for: tv), spoken: false) }
                }
            }
        }
    }

    private func quickToggleText(for tv: TVStatus) -> String {
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
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { showSettings = false } }
        }
        .presentationDetents([.medium])
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
        } catch {
            reply = "Couldn't reach the house server — are you home?"
            serverReachable = false
        }
        await refreshStatus()
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

    private var isOn: Bool { tv.power == "on" }
    private var isAppleTVRoom: Bool { tv.power == "via apple tv" }

    private var roomName: String {
        tv.name
            .replacingOccurrences(of: "-frame", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: isAppleTVRoom ? "appletv.fill" : "tv")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isOn ? .white : .white.opacity(0.45))
                    Spacer()
                    Circle()
                        .fill(isOn ? Color.green : (isAppleTVRoom ? Color.cyan.opacity(0.7) : Color.white.opacity(0.2)))
                        .frame(width: 8, height: 8)
                        .shadow(color: isOn ? .green.opacity(0.8) : .clear, radius: 4)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(roomName)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(isAppleTVRoom ? "Apple TV" : (isOn ? "On" : "Off"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(isOn ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(isOn ? 0.18 : 0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}
