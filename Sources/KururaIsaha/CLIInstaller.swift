import Foundation

/// Puts `kurura` on the user's PATH.
///
/// Never asks for an administrator password. `/usr/local/bin` is used when it already
/// exists and is writable (the common case on a Mac with Homebrew), and otherwise the link
/// goes in `~/.local/bin`, which needs no privileges at all. A timer app has no business
/// prompting for credentials to install a symlink.
enum CLIInstaller {
    static let toolName = "kurura"

    /// The copy shipped inside the app bundle. Nil when running unbundled from `.build/`.
    static var bundledTool: URL? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/\(toolName)")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    private static var candidates: [URL] {
        [
            URL(fileURLWithPath: "/usr/local/bin"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin"),
        ]
    }

    /// Where a link already points, if one is installed.
    static var installedAt: URL? {
        candidates
            .map { $0.appendingPathComponent(toolName) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func install() -> String {
        guard let tool = bundledTool else {
            return "The command lives inside the app bundle. Build with ./build.sh and run the app from dist/ or /Applications first."
        }

        let manager = FileManager.default
        guard let directory = chooseDirectory() else {
            return "Could not find or create a writable bin directory."
        }
        let destination = directory.appendingPathComponent(toolName)

        do {
            // Only ever clear a path that is our own link or a previous copy of the tool.
            if manager.fileExists(atPath: destination.path) {
                let existing = try? manager.destinationOfSymbolicLink(atPath: destination.path)
                guard existing != nil || manager.isDeletableFile(atPath: destination.path) else {
                    return "Something else already lives at \(destination.path)."
                }
                try manager.removeItem(at: destination)
            }
            try manager.createSymbolicLink(at: destination, withDestinationURL: tool)
        } catch {
            return "Could not link into \(directory.path): \(error.localizedDescription)"
        }

        let onPath = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .contains { $0 == directory.path }
        return onPath || directory.path == "/usr/local/bin"
            ? "Installed at \(destination.path). Try: kurura 25m"
            : "Installed at \(destination.path). Add it to your PATH:\n  export PATH=\"\(directory.path):$PATH\""
    }

    private static func chooseDirectory() -> URL? {
        let manager = FileManager.default
        for candidate in candidates {
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue, manager.isWritableFile(atPath: candidate.path) { return candidate }
                continue
            }
            // Only ever create the one under the user's own home.
            if candidate.path.hasPrefix(NSHomeDirectory()) {
                if (try? manager.createDirectory(at: candidate, withIntermediateDirectories: true)) != nil {
                    return candidate
                }
            }
        }
        return nil
    }
}
