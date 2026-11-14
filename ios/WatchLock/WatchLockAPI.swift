import Foundation

/// What the server stores. The watch sets both fields.
struct WatchState: Codable, Equatable {
    var taxMinutes: Int
    /// The activity the watch assigned, if any.
    var activity: String?
    var source: String?
    var updatedAt: String?
}

enum WatchLockAPIError: LocalizedError {
    case badURL
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .badURL: return "The server URL in Config.swift isn't valid."
        case .http(401): return "Server rejected the API key in Config.swift."
        case .http(let code): return "Server error (HTTP \(code))."
        }
    }
}

enum WatchLockAPI {
    /// Returns the current state: dummy data in .locked / .unlocked, the server in .live.
    static func fetchState() async throws -> WatchState {
        switch Config.mode {
        case .locked:
            try? await Task.sleep(for: .milliseconds(400)) // feel like a real request
            return WatchState(taxMinutes: Config.testTaxMinutes, activity: Config.testActivity, source: "test")
        case .unlocked:
            try? await Task.sleep(for: .milliseconds(400))
            return WatchState(taxMinutes: 0, activity: nil, source: "test")
        case .live:
            return try await fetchFromServer()
        }
    }

    /// GET /state with a short timeout, so you're never left waiting.
    private static func fetchFromServer() async throws -> WatchState {
        var base = Config.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/state") else { throw WatchLockAPIError.badURL }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        if !Config.apiKey.isEmpty {
            req.setValue(Config.apiKey, forHTTPHeaderField: "x-api-key")
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WatchLockAPIError.http(http.statusCode)
        }
        return try JSONDecoder().decode(WatchState.self, from: data)
    }
}
