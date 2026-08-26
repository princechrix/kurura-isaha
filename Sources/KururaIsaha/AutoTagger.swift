import AppKit
import Foundation

/// Names a session after whatever the user was actually doing.
///
/// Bundle identifiers only. Reading a browser's current URL would mean asking for
/// Accessibility permission, which is a heavy price for a nicer tag, so a browser is
/// simply "Browsing" until the user renames it.
enum AutoTagger {
    private static let rules: [String: String] = [
        "com.apple.dt.Xcode": "Coding",
        "com.microsoft.VSCode": "Coding",
        "com.todesktop.230313mzl4w4u92": "Coding",   // Cursor
        "dev.zed.Zed": "Coding",
        "com.jetbrains.intellij": "Coding",
        "com.sublimetext.4": "Coding",
        "com.apple.Terminal": "Terminal",
        "com.googlecode.iterm2": "Terminal",
        "dev.warp.Warp-Stable": "Terminal",
        "us.zoom.xos": "Meeting",
        "com.microsoft.teams2": "Meeting",
        "com.hnc.Discord": "Comms",
        "com.tinyspeck.slackmacgap": "Comms",
        "com.apple.mail": "Email",
        "com.figma.Desktop": "Design",
        "com.bohemiancoding.sketch3": "Design",
        "com.apple.Notes": "Writing",
        "md.obsidian": "Writing",
        "notion.id": "Writing",
        "com.apple.Safari": "Browsing",
        "com.google.Chrome": "Browsing",
        "org.mozilla.firefox": "Browsing",
        "company.thebrowser.Browser": "Browsing",
    ]

    /// The tag for whatever is frontmost right now, or nil when nothing is.
    static func currentTag() -> String? {
        guard Settings.shared.autoTag else { return nil }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        if let identifier = app.bundleIdentifier, let mapped = rules[identifier] { return mapped }
        // An unmapped app is still better than no tag: use its own name.
        return app.localizedName
    }

    static func tag(forBundleIdentifier identifier: String) -> String? {
        rules[identifier]
    }
}
