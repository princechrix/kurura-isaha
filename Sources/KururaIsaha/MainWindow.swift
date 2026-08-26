import AppKit
import KururaCore
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case analytics
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .analytics: return "Analytics"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .analytics: return "chart.bar.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

final class WindowState: ObservableObject {
    @Published var section: AppSection = .analytics
}

struct RootView: View {
    @ObservedObject var state: WindowState
    @ObservedObject var engine: TimerEngine
    let store: SessionStore

    var body: some View {
        TabView(selection: $state.section) {
            AnalyticsView(store: store, engine: engine)
                .tabItem { Label(AppSection.analytics.title, systemImage: AppSection.analytics.symbol) }
                .tag(AppSection.analytics)
            SettingsView(engine: engine)
                .tabItem { Label(AppSection.settings.title, systemImage: AppSection.settings.symbol) }
                .tag(AppSection.settings)
        }
        .padding(.top, 10)
        .frame(minWidth: 640, minHeight: 560)
    }
}

/// One window, opened on demand from the menu. The app is an accessory, so this is the
/// only thing that ever brings it forward.
final class MainWindowController: NSObject, NSWindowDelegate {
    private let state = WindowState()
    private let engine: TimerEngine
    private let store: SessionStore
    private var window: NSWindow?

    init(engine: TimerEngine, store: SessionStore) {
        self.engine = engine
        self.store = store
    }

    func show(_ section: AppSection) {
        state.section = section
        if window == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let hosting = NSHostingController(
            rootView: RootView(state: state, engine: engine, store: store))
        let created = NSWindow(contentViewController: hosting)
        created.title = "Kurura Isaha"
        created.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        created.setContentSize(NSSize(width: 700, height: 620))
        created.center()
        created.isReleasedWhenClosed = false
        created.delegate = self
        window = created
    }
}
