import AppKit
import Foundation

/// Stores per-account custom icons as image files under
/// `~/Library/Application Support/OpenUsage/AccountIcons`, referenced by `ProviderAccount.iconFileName`.
///
/// Icons render as monochrome **template** images everywhere (matching the app's monochrome design
/// language and the menu-bar template requirement), so a transparent glyph reads best; an opaque image
/// becomes a solid silhouette.
@MainActor
enum AccountIconStore {
    private static var cache: [String: NSImage] = [:]

    /// Storage directory (created on demand).
    static var directory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenUsage/AccountIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Copy a user-picked image into storage for the given account; returns the stored file name to
    /// persist on the account. Replaces any previous icon for that account.
    static func save(imageAt sourceURL: URL, for accountID: String) throws -> String {
        removeIcon(forAccountID: accountID)
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension.lowercased()
        let fileName = "\(sanitize(accountID)).\(ext)"
        let dest = directory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        cache[fileName] = nil
        return fileName
    }

    /// Load a stored icon by file name (cached).
    static func image(named fileName: String) -> NSImage? {
        if let cached = cache[fileName] { return cached }
        guard let image = NSImage(contentsOf: directory.appendingPathComponent(fileName)) else { return nil }
        cache[fileName] = image
        return image
    }

    /// Delete a stored icon file by name.
    static func delete(fileName: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
        cache[fileName] = nil
    }

    /// Remove any icon file(s) belonging to an account id (any extension).
    static func removeIcon(forAccountID accountID: String) {
        let prefix = sanitize(accountID) + "."
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: file)
            cache[file.lastPathComponent] = nil
        }
    }

    private static func sanitize(_ accountID: String) -> String {
        String(accountID.map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }
}
