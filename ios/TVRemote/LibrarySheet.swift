import SwiftUI

/// The gallery: every artwork the household has generated or cropped, served
/// from the Mac's library. Tap one to see it big, re-hang it on any Frame,
/// or remove it from the library.
struct LibrarySheet: View {
    let tvs: [TVStatus]
    let client: ServerClient?
    let onFinished: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [LibraryItem] = []
    @State private var loading = true
    @State private var errorText: String?
    @State private var selected: LibraryItem?
    @State private var sendingTo: String?

    private var frameTVs: [TVStatus] {
        // Same rule as ArtworkSheet: a sleeping Frame can't prove it's a
        // Frame, so keep sleeping TVs pickable.
        tvs.filter { $0.host != "-" && ($0.supportsArtMode || $0.power != "on") }
    }

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(.white.opacity(0.25))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            HStack {
                if selected != nil {
                    Button {
                        selected = nil
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 32, height: 32)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .disabled(sendingTo != nil)
                }
                Spacer()
            }
            .overlay(
                Text(selected == nil ? "Library" : caption(for: selected!))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            )
            .padding(.horizontal, 24)

            if let selected {
                detail(selected)
            } else {
                grid
            }
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.08, green: 0.07, blue: 0.14).ignoresSafeArea())
        .interactiveDismissDisabled(sendingTo != nil)
        .task { await load() }
    }

    // MARK: grid

    private var grid: some View {
        Group {
            if loading {
                ProgressView().tint(.white.opacity(0.7)).frame(maxHeight: .infinity)
            } else if let errorText {
                Text(errorText)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .frame(maxHeight: .infinity)
            } else if items.isEmpty {
                Text("Nothing here yet — everything you imagine or hang\nends up in this gallery.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(items) { item in
                            Button {
                                selected = item
                            } label: {
                                thumb(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func thumb(_ item: LibraryItem) -> some View {
        AsyncImage(url: client?.thumbURL(for: item.id)) { phase in
            if case .success(let image) = phase {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.white.opacity(0.06))
                    .overlay(
                        Image(systemName: item.kind == "generated" ? "sparkles" : "photo")
                            .foregroundStyle(.white.opacity(0.25))
                    )
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if item.kind == "generated" {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(5)
                    .background(.black.opacity(0.45), in: Circle())
                    .padding(6)
            }
        }
    }

    // MARK: detail

    private func detail(_ item: LibraryItem) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                AsyncImage(url: client?.imageURL(for: item.id)) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Rectangle().fill(.white.opacity(0.06))
                            .overlay(ProgressView().tint(.white.opacity(0.5)))
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )

                if let prompt = item.prompt, !prompt.isEmpty {
                    Text("“\(prompt)”")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }

                if let sendingTo {
                    HStack(spacing: 10) {
                        ProgressView().tint(.white.opacity(0.7))
                        Text("Hanging it on the \(roomName(sendingTo)) TV…")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.vertical, 20)
                } else {
                    VStack(spacing: 10) {
                        Text("Hang it on…")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                        ForEach(frameTVs) { tv in
                            Button {
                                Task { await hang(item, on: tv) }
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
                        Button(role: .destructive) {
                            Task { await removeFromLibrary(item) }
                        } label: {
                            Label("Remove from library", systemImage: "trash")
                                .font(.system(.footnote, design: .rounded).weight(.medium))
                        }
                        .tint(.red.opacity(0.85))
                        .padding(.top, 8)
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.orange.opacity(0.9))
                }
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: work

    private func load() async {
        guard let client else {
            errorText = "Set the server address in settings."
            loading = false
            return
        }
        do {
            items = try await client.library()
            errorText = nil
        } catch {
            errorText = "Couldn't load the library — is the server up to date?"
        }
        loading = false
    }

    private func hang(_ item: LibraryItem, on tv: TVStatus) async {
        guard let client else { return }
        sendingTo = tv.name
        defer { sendingTo = nil }
        do {
            let result = try await client.hangFromLibrary(tv: tv.name, id: item.id)
            onFinished(result.reply)
            dismiss()
        } catch {
            errorText = "Couldn't hang it — are you home?"
        }
    }

    private func removeFromLibrary(_ item: LibraryItem) async {
        guard let client else { return }
        do {
            _ = try await client.deleteLibraryItem(id: item.id)
            items.removeAll { $0.id == item.id }
            selected = nil
        } catch {
            errorText = "Couldn't remove it — try again."
        }
    }

    private func caption(for item: LibraryItem) -> String {
        item.kind == "generated" ? "Imagined" : "From a photo"
    }

    private func roomName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "-frame", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}
