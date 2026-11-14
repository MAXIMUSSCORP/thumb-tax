import Foundation

/// What the server stores. The watch sets taxMinutes, activity and creditMinutes.
struct WatchState: Codable, Equatable {
    var taxMinutes: Int
    /// The activity the watch assigned, if any.
    var activity: String?
    /// Earned scroll time in minutes (shown when taxMinutes is 0).
    var creditMinutes: Int?
    /// Guarded-app minutes reported today (the running total POST /usage adds to).
    var usedMinutesToday: Int?
    /// The day usedMinutesToday belongs to, "YYYY-MM-DD".
    var usageDay: String?
    var source: String?
    var updatedAt: String?
}

enum WatchLockAPIError: LocalizedError {
    case badURL
    case conflict
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .badURL: return "The server URL in Config.swift isn't valid."
        case .conflict: return "The server's usage count changed. Try again."
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
            return WatchState(taxMinutes: 0, activity: nil, creditMinutes: Config.testCreditMinutes, source: "test")
        case .live:
            return try await request("/state")
        }
    }

    /// "Scroll anyway": adds `minutes` to today's usage with POST /usage. The watch then charges it
    /// as tax. The app never writes taxMinutes itself (the watch owns it).
    /// Sends the running total for today, as the server expects, and retries once on a 409.
    static func addUsage(minutes: Int) async throws -> WatchState {
        guard Config.mode == .live else { return try await fetchState() } // test modes: no network

        var current: WatchState = try await request("/state")
        for attempt in 0..<2 {
            let today = localDay()
            let base = current.usageDay == today ? (current.usedMinutesToday ?? 0) : 0
            let total = min(1440, max(0, base + minutes))
            do {
                return try await request("/usage", method: "POST",
                                         body: ["usedMinutesToday": total, "day": today])
            } catch WatchLockAPIError.conflict where attempt == 0 {
                current = try await request("/state") // server moved on: re-read and add on top
            }
        }
        throw WatchLockAPIError.conflict
    }

    /// The phone's local date, "YYYY-MM-DD".
    static func localDay(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// One HTTP call to the server with a short timeout, so you're never left waiting.
    private static func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> WatchState {
        var base = Config.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        // Cache-buster on reads, so neither iOS nor a tunnel/proxy (e.g. Cloudflare) hands back an old /state.
        let query = method == "GET" ? "?t=\(Int(Date().timeIntervalSince1970 * 1000))" : ""
        guard let url = URL(string: base + path + query) else { throw WatchLockAPIError.badURL }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 8)
        req.httpMethod = method
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if !Config.apiKey.isEmpty {
            req.setValue(Config.apiKey, forHTTPHeaderField: "x-api-key")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw http.statusCode == 409 ? WatchLockAPIError.conflict : WatchLockAPIError.http(http.statusCode)
        }
        return try JSONDecoder().decode(WatchState.self, from: data)
    }
}
