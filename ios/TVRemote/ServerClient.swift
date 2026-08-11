import Foundation

struct TVStatus: Decodable, Identifiable {
    let name: String
    let host: String
    let power: String
    let apple_tv: Bool
    var id: String { name }
}

struct CommandReply: Decodable {
    let reply: String
    let fast_path: Bool
}

/// Thin client for the home server running on the Mac.
final class ServerClient {
    let baseURL: URL

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
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(CommandReply.self, from: data)
    }

    func status() async throws -> [TVStatus] {
        let (data, _) = try await URLSession.shared.data(
            from: baseURL.appending(path: "status"))
        return try JSONDecoder().decode([TVStatus].self, from: data)
    }
}
