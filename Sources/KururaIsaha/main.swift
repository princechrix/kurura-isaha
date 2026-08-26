import AppKit
import Foundation
import KururaCore

let arguments = Array(CommandLine.arguments.dropFirst())

func printUsage() {
    print("""
    Kurura Isaha — pull a timer out of the menu bar.

    Usage:
      KururaIsaha              run the menu bar app (default)
      KururaIsaha --where      print the paths this app uses
      KururaIsaha --version    print the version
      KururaIsaha --help       this text

    Everything else lives in the `kurura` CLI, which talks to a running app:
      kurura start --duration 25m --tag "Debugging"
    """)
}

if arguments.contains("--help") || arguments.contains("-h") {
    printUsage()
    exit(0)
}

if arguments.contains("--version") || arguments.contains("-v") {
    print(KururaVersion.line)
    exit(0)
}

if arguments.contains("--where") {
    print("support directory  \(ControlPaths.supportDirectory.path)")
    print("database           \(ControlPaths.databaseURL.path)")
    print("control socket     \(ControlPaths.socketPath)")
    exit(0)
}

// Used by build.sh. The icon is drawn from source on every build rather than committed as
// a binary blob, so it stays diffable and cannot drift from the palette the app uses.
if let index = arguments.firstIndex(of: "--render-icon") {
    guard index + 1 < arguments.count else {
        FileHandle.standardError.write(Data("--render-icon needs an output .iconset directory\n".utf8))
        exit(64)
    }
    let directory = URL(fileURLWithPath: arguments[index + 1])
    do {
        try IconArtwork.writeIconset(to: directory)
        print("wrote \(IconArtwork.iconsetEntries.count) images to \(directory.path)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("could not write the iconset: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

if let unknown = arguments.first(where: { $0.hasPrefix("-") }) {
    FileHandle.standardError.write(Data("unknown option: \(unknown)\n".utf8))
    printUsage()
    exit(64)
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
// A menu bar accessory: no Dock icon, no application menu. The status item and the
// windows it opens are the whole interface.
application.setActivationPolicy(.accessory)
application.run()
