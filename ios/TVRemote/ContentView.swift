import SwiftUI

struct ContentView: View {
    @AppStorage("serverURL") private var serverURLString = "http://macbook.local:8765"

    @StateObject private var speech = SpeechRecognizer()
    @State private var tvs: [TVStatus] = []
    @State private var reply: String = "Hold the circle and tell your TVs what to do."
    @State private var busy = false
    @State private var showSettings = false

    private var client: ServerClient? {
        URL(string: serverURLString).map(ServerClient.init)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                tvGrid
                Spacer()
                transcriptView
                Spacer()
                talkButton
                    .padding(.bottom, 32)
            }
            .padding()
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("TV")
            .toolbar {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                }
            }
            .sheet(isPresented: $showSettings) { settings }
        }
        .task {
            speech.requestPermissions()
            await refreshStatus()
        }
    }

    // MARK: pieces

    private var tvGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
            ForEach(tvs) { tv in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Circle()
                            .fill(tv.power == "on" ? .green : .gray.opacity(0.4))
                            .frame(width: 10, height: 10)
                        Text(tv.name.replacingOccurrences(of: "-", with: " ").capitalized)
                            .font(.headline)
                    }
                    Text(tv.apple_tv ? "Apple TV" : "Samsung only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var transcriptView: some View {
        VStack(spacing: 12) {
            if speech.isListening {
                Text(speech.transcript.isEmpty ? "Listening…" : speech.transcript)
                    .font(.title2.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
            } else {
                Text(reply)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(busy ? .secondary : .primary)
            }
        }
        .frame(minHeight: 90)
        .animation(.easeInOut(duration: 0.15), value: speech.transcript)
    }

    private var talkButton: some View {
        ZStack {
            // pulsing ring driven by mic level
            Circle()
                .stroke(Color.accentColor.opacity(0.5), lineWidth: 3)
                .frame(width: 130, height: 130)
                .scaleEffect(speech.isListening ? 1 + CGFloat(speech.level) * 0.5 : 1)
                .opacity(speech.isListening ? 1 : 0)
                .animation(.easeOut(duration: 0.1), value: speech.level)

            Circle()
                .fill(speech.isListening ? Color.accentColor : Color.white.opacity(0.12))
                .frame(width: 110, height: 110)
                .overlay {
                    if busy {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white)
                    }
                }
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
        .sensoryFeedback(.impact, trigger: speech.isListening)
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section("Home server") {
                    TextField("http://macbook.local:8765", text: $serverURLString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                Button("Done") { showSettings = false }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: actions

    private func send(_ text: String) async {
        guard let client else {
            reply = "Set the server address in settings."
            return
        }
        busy = true
        reply = "…"
        do {
            let result = try await client.send(text)
            reply = result.reply
        } catch {
            reply = "Couldn't reach the house server — are you home?"
        }
        busy = false
        await refreshStatus()
    }

    private func refreshStatus() async {
        guard let client else { return }
        if let status = try? await client.status() {
            tvs = status
        }
    }
}

#Preview {
    ContentView()
}
