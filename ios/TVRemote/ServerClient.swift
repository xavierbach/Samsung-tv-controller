import Foundation

struct TVStatus: Decodable, Identifiable {
    let name: String
    let host: String
    let power: String
    let apple_tv: Bool
    let art_mode: Bool?  // optional so older servers still decode
    var id: String { name }

    var supportsArtMode: Bool { art_mode ?? false }
}

struct CommandReply: Decodable {
    let reply: String
    let fast_path: Bool
}

/// Thin client for the home server running on the Mac.
final class ServerClient {
    let baseURL: URL

    // Away from home the server is reached over a VPN (Tailscale), and iOS
    // tears that tunnel down in the background: the first request after the
    // app wakes has no route yet. waitsForConnectivity holds the request
    // until the tunnel is back instead of failing instantly; the resource
    // timeout bounds how long we'll hold on.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 45
        return URLSession(configuration: config)
    }()

    // Artwork uploads are already given 180s; keep their ceiling above that.
    private static let uploadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 240
        return URLSession(configuration: config)
    }()

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func send(_ text: String, room: String? = nil) async throws -> CommandReply {
        var request = URLRequest(url: baseURL.appending(path: "command"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        var body: [String: String] = ["text": text, "source": "iphone"]
        if let room { body["room"] = room }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await Self.session.data(for: request)
        return try JSONDecoder().decode(CommandReply.self, from: data)
    }

    func status() async throws -> [TVStatus] {
        let (data, _) = try await Self.session.data(
            from: baseURL.appending(path: "status"))
        return try JSONDecoder().decode([TVStatus].self, from: data)
    }

    /// Upload a 16:9 JPEG and set it as the Frame TV's Art Mode artwork.
    func setArtwork(tv: String, jpeg: Data) async throws -> CommandReply {
        var request = URLRequest(url: baseURL.appending(path: "artwork"))
        request.httpMethod = "POST"
        // Waking the TV + pushing a 4K image over its art socket is slow.
        request.timeoutInterval = 180

        let boundary = "tvctl-\(UUID().uuidString)"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"tv\"\r\n\r\n\(tv)\r\n".utf8))
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data(
            "Content-Disposition: form-data; name=\"image\"; filename=\"artwork.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let (data, _) = try await Self.uploadSession.upload(for: request, from: body)
        return try JSONDecoder().decode(CommandReply.self, from: data)
    }
}
