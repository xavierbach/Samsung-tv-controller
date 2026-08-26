import PhotosUI
import SwiftUI
import UIKit

/// The Art Studio: describe artwork in words, optionally pick a style and a
/// reference photo, and the house server paints it with AI (16:9, Frame-
/// ready). Preview the result, then hand it off to the TV picker to hang.
struct ArtStudioSheet: View {
    let client: ServerClient?
    let onReady: (ArtworkImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var style: String?
    @State private var referenceItem: PhotosPickerItem?
    @State private var referenceImage: UIImage?
    @State private var generating = false
    @State private var result: ArtworkImage?
    @State private var errorText: String?
    @FocusState private var promptFocused: Bool

    private static let styles = [
        "Oil painting", "Watercolor", "Impressionist", "Japanese woodblock",
        "Minimal line art", "Abstract", "Pop art", "Photorealistic",
    ]

    private var promptReady: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(.white.opacity(0.25))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            Text(result == nil ? "Art Studio" : "Your artwork")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.white)

            if let result {
                preview(result)
            } else {
                form
            }
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.08, green: 0.07, blue: 0.14).ignoresSafeArea())
        .interactiveDismissDisabled(generating)
        .onChange(of: referenceItem) { _, item in
            guard let item else { return }
            Task { await loadReference(item) }
        }
    }

    // MARK: compose

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Describe it, pick a style, and hang it on a Frame.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                TextField(
                    "A misty eucalypt forest at dawn…",
                    text: $prompt, axis: .vertical
                )
                .lineLimit(3...6)
                .focused($promptFocused)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white)
                .tint(.white)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.08))
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.styles, id: \.self) { s in
                            Button {
                                style = (style == s ? nil : s)
                            } label: {
                                Text(s)
                                    .font(.system(.footnote, design: .rounded).weight(.medium))
                                    .foregroundStyle(style == s ? .black : .white.opacity(0.85))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule().fill(style == s ? Color.white : Color.white.opacity(0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: 12) {
                    PhotosPicker(selection: $referenceItem, matching: .images) {
                        Label(
                            referenceImage == nil ? "Start from a photo" : "Change photo",
                            systemImage: "photo.on.rectangle.angled"
                        )
                        .font(.system(.footnote, design: .rounded).weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(.white.opacity(0.1)))
                    }
                    if let referenceImage {
                        Image(uiImage: referenceImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Button {
                            self.referenceImage = nil
                            referenceItem = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }

                if let errorText {
                    Text(errorText)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.orange.opacity(0.9))
                }

                generateButton
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
    }

    private var generateButton: some View {
        Button {
            Task { await generate() }
        } label: {
            HStack(spacing: 8) {
                if generating {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(generating ? "Painting…" : "Create artwork")
                    .font(.system(.body, design: .rounded).weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.95, green: 0.55, blue: 0.35),
                                Color(red: 0.75, green: 0.35, blue: 0.95),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(generating || !promptReady)
        .opacity(promptReady ? 1 : 0.5)
    }

    // MARK: result

    private func preview(_ art: ArtworkImage) -> some View {
        VStack(spacing: 14) {
            Image(uiImage: art.preview)
                .resizable()
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )
                .padding(.horizontal, 24)

            if generating {
                HStack(spacing: 10) {
                    ProgressView().tint(.white.opacity(0.7))
                    Text("Painting another…")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.vertical, 12)
            } else {
                Button {
                    onReady(art)
                    dismiss()
                } label: {
                    Label("Hang it on a TV", systemImage: "photo.artframe")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.95, green: 0.55, blue: 0.35),
                                            Color(red: 0.75, green: 0.35, blue: 0.95),
                                        ],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                )
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)

                HStack(spacing: 10) {
                    Button {
                        Task { await generate() }
                    } label: {
                        Label("Try another", systemImage: "arrow.clockwise")
                    }
                    Button {
                        result = nil
                    } label: {
                        Label("Edit prompt", systemImage: "pencil")
                    }
                }
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.4))
            }

            if let errorText {
                Text(errorText)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.orange.opacity(0.9))
                    .padding(.horizontal, 24)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: work

    private func generate() async {
        guard let client else {
            errorText = "Set the server address in settings."
            return
        }
        promptFocused = false
        generating = true
        errorText = nil
        defer { generating = false }

        var fullPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if let style {
            fullPrompt += ". Style: \(style.lowercased())."
        }
        let reference = referenceImage.flatMap { Self.jpegForUpload($0) }
        do {
            let art = try await client.generateArt(prompt: fullPrompt, reference: reference)
            guard let b64 = art.image_b64,
                  let data = Data(base64Encoded: b64),
                  let image = UIImage(data: data),
                  let prepared = await prepare(image)
            else {
                // No image means the server said why in the reply.
                errorText = art.reply
                return
            }
            withAnimation(.easeInOut(duration: 0.25)) { result = prepared }
        } catch {
            errorText = "Couldn't reach the studio — \(error.localizedDescription)"
        }
    }

    /// The generated image is already 16:9, so SmartCropper just normalizes,
    /// bounds it to the Frame's resolution, and produces the upload JPEG.
    private func prepare(_ image: UIImage) async -> ArtworkImage? {
        await Task.detached(priority: .userInitiated) {
            SmartCropper.artwork(from: image)
        }.value
    }

    private func loadReference(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else {
            errorText = "Couldn't read that photo — try another one."
            return
        }
        referenceImage = image
    }

    /// Shrink the reference before upload: the model only needs the gist of
    /// it, and a 48MP HEIC would slow the round trip right down.
    private static func jpegForUpload(_ image: UIImage) -> Data? {
        let maxDim: CGFloat = 1536
        let size = image.size
        let scale = min(1, maxDim / max(size.width, size.height))
        guard scale < 1 else { return image.jpegData(compressionQuality: 0.85) }
        let out = CGSize(
            width: (size.width * scale).rounded(),
            height: (size.height * scale).rounded()
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let scaled = UIGraphicsImageRenderer(size: out, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: out))
        }
        return scaled.jpegData(compressionQuality: 0.85)
    }
}
