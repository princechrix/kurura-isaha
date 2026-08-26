import Foundation

/// The version, read back out of the bundle that VERSION was baked into at build time,
/// so it is never written down in two places.
///
/// The CLI gets this for free: a binary at `Kurura Isaha.app/Contents/MacOS/kurura` still
/// resolves `Bundle.main` to the enclosing app. Run either one straight out of `.build/`
/// and there is no Info.plist to read, hence the fallback.
public enum KururaVersion {
    public static let string: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }()

    public static var line: String { "Kurura Isaha \(string)" }
}
