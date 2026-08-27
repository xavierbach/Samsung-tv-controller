import SwiftUI
import UIKit

/// Shown after a photo is picked and smart-cropped: previews the 16:9 result
/// and asks which Frame TV should hang it, then uploads.
struct ArtworkSheet: View {
    let artwork: ArtworkImage
    let tvs: [TVStatus]
    let client: ServerClient?
    let onFinished: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sendingTo: String?

    private var frameTVs: [TVStatus] {
        // A deeply asleep Frame doesn't answer the art-mode probe, so only an
        // awake TV reporting false is definitely not a Frame. Sleeping TVs
        // stay pickable — the server wakes the chosen one and checks for real.
        tvs.filter { $0.host != "-" && ($0.supportsArtMode || $0.power != "on") }
    }

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(.white.opacity(0.25))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            Text("Set as artwork")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.white)

            Image(uiImage: artwork.preview)
                .resizable()
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )
                .padding(.horizontal, 24)

            Text("Cropped to 16:9 around what matters.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))

            if let sendingTo {
                HStack(spacing: 10) {
                    ProgressView().tint(.white.opacity(0.7))
                    Text("Hanging it on the \(roomName(sendingTo)) TV…")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxHeight: .infinity)
            } else if frameTVs.isEmpty {
                Text("No Frame TVs found — Art Mode needs a Samsung Frame.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    Text("Which TV should show it?")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    ForEach(frameTVs) { tv in
                        Button {
                            Task { await send(to: tv) }
                        } label: {
                            HStack {
                                Image(systemName: "photo.artframe")
                                    .font(.system(size: 16, weight: .semibold))
                                Text(roomName(tv.name))
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.white.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                Spacer(minLength: 0)
            }
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.07, blue: 0.14).ignoresSafeArea())
        .interactiveDismissDisabled(sendingTo != nil)
    }

    private func roomName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "-frame", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func send(to tv: TVStatus) async {
        guard let client else {
            onFinished("Set the server address in settings.")
            dismiss()
            return
        }
        sendingTo = tv.name
        defer { sendingTo = nil }
        do {
            // Generated art is already archived on the server — hang it by
            // library id instead of pushing the JPEG over the network again.
            let result: CommandReply
            if let libraryId = artwork.libraryId {
                result = try await client.hangFromLibrary(tv: tv.name, id: libraryId)
            } else {
                result = try await client.setArtwork(tv: tv.name, jpeg: artwork.jpeg)
            }
            onFinished(result.reply)
        } catch {
            onFinished("Couldn't send the artwork — are you home?")
        }
        dismiss()
    }
}
