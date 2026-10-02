import AppKit
import CoreText

/// `Contents/Resources/bundled-fonts` in the app; the repo copy for debug builds outside an app bundle
func bundledFontURLs() -> [URL] {
    var dir = Bundle.main.resourceURL?.appending(path: "bundled-fonts")
    if dir.map({ !FileManager.default.fileExists(atPath: $0.path) }) ?? true {
        var url = URL(filePath: #filePath)
        while url.path != "/" {
            url.deleteLastPathComponent()
            let candidate = url.appending(path: "bundled-fonts")
            if FileManager.default.fileExists(atPath: candidate.path) {
                dir = candidate
                break
            }
        }
    }
    guard let dir, let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
    return files.filter { $0.pathExtension == "ttf" }
}

/// For this process only: the bar's icons work without installing the font system-wide
@discardableResult
func registerBundledFonts() -> Bool {
    var ok = true
    for url in bundledFontURLs() {
        var error: Unmanaged<CFError>? = nil
        let registered = unsafe CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        guard !registered, let error = unsafe error?.takeRetainedValue() else { continue }
        if CFErrorGetCode(error) != CTFontManagerError.alreadyRegistered.rawValue { ok = false }
    }
    return ok
}
