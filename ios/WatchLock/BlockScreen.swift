import UIKit

/// Reads the app name from the shortcut's link: thumbtax://open?app=Instagram (or thumbtax://Instagram).
enum ShortcutLink {
    static func appName(from url: URL) -> String? {
        guard url.scheme?.lowercased() == Config.urlScheme else { return nil }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let app = comps?.queryItems?.first(where: { $0.name.lowercased() == "app" })?.value, !app.isEmpty {
            return app
        }
        if let host = url.host, !host.isEmpty, host.lowercased() != "open" {
            return host
        }
        return nil
    }
}

enum AppLauncher {
    static func url(for appName: String) -> URL? {
        let key = appName.trimmingCharacters(in: .whitespaces).lowercased()
        return Config.appURLSchemes[key].flatMap(URL.init(string:))
    }

    /// Opens the real app. Returns false if it isn't installed or has no known scheme.
    @MainActor
    static func open(_ appName: String) async -> Bool {
        guard let url = url(for: appName) else { return false }
        return await UIApplication.shared.open(url)
    }
}

enum HomeScreen {
    /// Sends the app to the background, which drops you on the Home Screen.
    /// Uses a private selector: fine for a hackathon demo, would be rejected by App Review.
    static func go() {
        UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
    }
}
