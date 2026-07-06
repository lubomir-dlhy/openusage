import AppKit
import Foundation
import Testing
@testable import OpenUsage

@MainActor
struct AccountIconStoreTests {
    /// Writes a tiny valid PNG to a temp file and returns its URL.
    private func makeTempPNG() throws -> URL {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let png = rep.representation(using: .png, properties: [:])!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ou-icon-\(UUID().uuidString).png")
        try png.write(to: url)
        return url
    }

    @Test func saveLoadDeleteRoundTrip() throws {
        let source = try makeTempPNG()
        defer { try? FileManager.default.removeItem(at: source) }
        let accountID = "claude#test-\(UUID().uuidString)"

        let fileName = try AccountIconStore.save(imageAt: source, for: accountID)
        #expect(fileName.hasSuffix(".png"))
        #expect(AccountIconStore.image(named: fileName) != nil)

        AccountIconStore.delete(fileName: fileName)
        #expect(AccountIconStore.image(named: fileName) == nil)
    }

    @Test func savingReplacesPreviousIconForAccount() throws {
        let accountID = "codex#test-\(UUID().uuidString)"
        let first = try makeTempPNG(); defer { try? FileManager.default.removeItem(at: first) }
        let second = try makeTempPNG(); defer { try? FileManager.default.removeItem(at: second) }

        let firstName = try AccountIconStore.save(imageAt: first, for: accountID)
        let secondName = try AccountIconStore.save(imageAt: second, for: accountID)
        // Same account, same extension ⇒ same file name, and the old icon is gone.
        #expect(firstName == secondName)
        AccountIconStore.removeIcon(forAccountID: accountID)
        #expect(AccountIconStore.image(named: secondName) == nil)
    }

    @Test func providerUsesCustomIconWhenSet() {
        let custom = ProviderAccount(id: "claude#9", providerID: "claude", label: "Work", configDir: nil, iconFileName: "x.png")
        #expect(ClaudeProvider(account: custom).provider.icon == .customFile("x.png"))
        #expect(ClaudeProvider(account: .makeDefault(providerID: "claude")).provider.icon == .providerMark("claude"))

        let codexCustom = ProviderAccount(id: "codex#9", providerID: "codex", label: "Work", configDir: nil, iconFileName: "y.png")
        #expect(CodexProvider(account: codexCustom).provider.icon == .customFile("y.png"))
    }
}
