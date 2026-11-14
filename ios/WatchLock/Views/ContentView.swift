import SwiftUI

/// The app's only screen. A Home Screen shortcut opens thumbtax://open?app=Instagram,
/// this screen checks the server, then:
///   0 tax minutes  -> green, "Open Instagram" button
///   more than 0    -> red, big number + the watch's activity, and you must go to the Home Screen
struct ContentView: View {
    private enum Phase: Equatable {
        case loading
        case loaded(WatchState)
        case failed(String)
    }

    @Environment(\.scenePhase) private var scenePhase

    @State private var phase: Phase = .loading
    @State private var refreshing = false
    /// Increments per request, so a slow older response never overwrites a newer one.
    @State private var requestID = 0
    @State private var refreshError: String?
    @State private var lastChecked: Date?
    /// The app the shortcut asked to open. Opened directly: Config.defaultApp.
    @State private var targetApp: String = Config.defaultApp
    @State private var openFailed = false
    @State private var scrollingAnyway = false
    @State private var scrollError: String?

    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private static let green = Color(red: 0.12, green: 0.62, blue: 0.36)
    private static let red = Color(red: 0.84, green: 0.19, blue: 0.19)

    // MARK: - Derived state

    private var state: WatchState? {
        if case .loaded(let s) = phase { return s }
        return nil
    }

    private var minutes: Int? { state?.taxMinutes }
    private var isClear: Bool { (minutes ?? 1) <= 0 }
    private var isBlocked: Bool { state != nil && !isClear }

    private var background: Color {
        switch phase {
        case .loading, .failed: return Color(white: 0.35)
        case .loaded: return isClear ? Self.green : Self.red
        }
    }

    /// Only from the server (set by the watch). nil = none assigned yet.
    private var activity: String? {
        guard let a = state?.activity?.trimmingCharacters(in: .whitespaces), !a.isEmpty else { return nil }
        return a
    }

    // MARK: - View

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer(minLength: 8)
                header
                numberBlock
                if isBlocked { activityCard }
                if state != nil && isClear { creditCard }
                if case .failed(let message) = phase {
                    Text(message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .opacity(0.85)
                }
                refreshRow
                Spacer()
                actions
            }
            .padding(24)
            .foregroundStyle(.white)

            if Config.mode != .live { testModeBadge }
        }
        .animation(.easeInOut(duration: 0.3), value: phase)
        .onOpenURL { url in
            // The shortcut: thumbtax://open?app=Instagram
            targetApp = ShortcutLink.appName(from: url) ?? Config.defaultApp
            Task { await load(fresh: true) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await load(fresh: true) } }
        }
        .task { await load(fresh: true) }
        .onReceive(timer) { _ in Task { await load(fresh: false) } }
    }

    /// Reminder that the screen is showing dummy data, not the server.
    private var testModeBadge: some View {
        VStack {
            Text(Config.mode == .locked ? "TEST MODE · LOCKED" : "TEST MODE · UNLOCKED")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(.black.opacity(0.35)))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.top, 4)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
        }
    }

    private var icon: String {
        switch phase {
        case .loading: return "hourglass"
        case .failed: return "wifi.exclamationmark"
        case .loaded: return isClear ? "lock.open.fill" : "lock.fill"
        }
    }

    private var title: String {
        switch phase {
        case .loading: return "Checking tax minutes…"
        case .failed: return "Can't reach the server"
        case .loaded:
            return isClear ? "\(targetApp) is unlocked" : "\(targetApp) is locked"
        }
    }

    private var numberBlock: some View {
        VStack(spacing: 0) {
            if phase == .loading {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .frame(height: 150)
            } else {
                Text(minutes.map(String.init) ?? "–")
                    .font(.system(size: 150, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .contentTransition(.numericText())
                Text(minutesLabel)
                    .font(.title3.weight(.medium))
                    .opacity(0.9)
            }
        }
    }

    private var minutesLabel: String {
        guard let minutes else { return "tax minutes" }
        let unit = minutes == 1 ? "tax minute" : "tax minutes"
        return minutes > 0 ? "\(unit) remaining" : unit
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Activity to complete", systemImage: "figure.walk")
                .font(.subheadline.weight(.semibold))
                .opacity(0.85)
            if let activity {
                Text(activity)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Waiting for your watch to assign one…")
                    .font(.body.italic())
                    .opacity(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.18)))
    }

    /// Green screen: the scroll time the watch says you've earned.
    private var creditCard: some View {
        let credit = max(0, state?.creditMinutes ?? 0)
        return VStack(spacing: 6) {
            Label("Earned scroll time", systemImage: "timer")
                .font(.subheadline.weight(.semibold))
                .opacity(0.85)
            Text(credit == 1 ? "1 minute" : "\(credit) minutes")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.18)))
    }

    private var refreshRow: some View {
        VStack(spacing: 6) {
            Button {
                Task { await load(fresh: false, manual: true) }
            } label: {
                Label(refreshing ? "Checking…" : "Refresh", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.white.opacity(0.2)))
            }
            if let refreshError {
                Text(refreshError)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .opacity(0.85)
            }
            if let lastChecked {
                Text("Checked \(lastChecked, style: .relative) ago")
                    .font(.caption)
                    .opacity(0.75)
            }
        }
    }

    /// Green: open the real app. Red: you have to go to the Home Screen.
    private var actions: some View {
        VStack(spacing: 12) {
            if isBlocked {
                Text("Pay off your tax minutes first.\nHead back to your Home Screen.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Button {
                    HomeScreen.go()
                } label: {
                    Label("Go to Home Screen", systemImage: "house.fill")
                }
                .buttonStyle(PillButtonStyle(primary: true, tint: background))

                if let scrollError {
                    Text(scrollError)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .opacity(0.85)
                }
                Button {
                    scrollAnyway()
                } label: {
                    Label(scrollingAnyway ? "Adding time…" : "Scroll anyway · +\(Config.scrollAnywayMinutes) min debt",
                          systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(PillButtonStyle(primary: false, tint: background))
                .disabled(scrollingAnyway)
            } else if isClear {
                let app = targetApp
                if openFailed {
                    Text("Couldn't open \(app). Is it installed?")
                        .font(.footnote)
                        .opacity(0.85)
                }
                Button {
                    Task { openFailed = !(await AppLauncher.open(app)) }
                } label: {
                    Label("Open \(app)", systemImage: "arrow.up.forward.app.fill")
                }
                .buttonStyle(PillButtonStyle(primary: true, tint: background))
            } else {
                // Opened directly, or the server couldn't be reached.
                Button {
                    HomeScreen.go()
                } label: {
                    Label("Go to Home Screen", systemImage: "house.fill")
                }
                .buttonStyle(PillButtonStyle(primary: false, tint: background))
            }
        }
    }

    // MARK: - Scroll anyway

    /// Reports extra usage (the watch adds it to the debt), then opens the app.
    /// If the time can't be recorded, the app is not opened.
    private func scrollAnyway() {
        scrollingAnyway = true
        scrollError = nil
        let app = targetApp
        Task {
            do {
                let s = try await WatchLockAPI.addUsage(minutes: Config.scrollAnywayMinutes)
                phase = .loaded(s)
                if !(await AppLauncher.open(app)) {
                    scrollError = "Time added, but couldn't open \(app). Is it installed?"
                }
            } catch {
                scrollError = "Couldn't add the time, so \(app) wasn't opened. \(error.localizedDescription)"
            }
            scrollingAnyway = false
        }
    }

    // MARK: - Loading

    /// fresh = just opened or came forward: show the spinner so a stale colour never flashes.
    /// manual = the Refresh button: always runs, even if an automatic check is still in flight.
    private func load(fresh: Bool, manual: Bool = false) async {
        // Only the 3-second timer skips when a request is already running.
        if refreshing && !fresh && !manual { return }
        requestID += 1
        let myID = requestID
        refreshing = true
        defer { if myID == requestID { refreshing = false } }

        if fresh {
            phase = .loading
            openFailed = false
        }

        do {
            let s = try await WatchLockAPI.fetchState()
            guard myID == requestID else { return } // a newer request already answered
            phase = .loaded(s)
            lastChecked = Date()
            refreshError = nil
        } catch {
            guard myID == requestID else { return }
            if !fresh, state != nil {
                // Keep the last good reading on screen, but tell the user when they asked.
                if manual { refreshError = "Couldn't refresh: \(error.localizedDescription)" }
                return
            }
            phase = .failed(error.localizedDescription)
        }
    }
}

/// Full-width rounded button: white with coloured text when primary, translucent when not.
private struct PillButtonStyle: ButtonStyle {
    let primary: Bool
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 14).fill(primary ? Color.white : Color.white.opacity(0.2)))
            .foregroundStyle(primary ? tint : Color.white)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

#Preview {
    ContentView()
}
