import Foundation

/// Whether Claude cards read billing dates through Claude Desktop's signed-in claude.ai session. Off by
/// default: that session is a full claude.ai login, so the user opts in from a Claude card's Customize page.
enum ClaudeDesktopBillingSetting {
    static let key = "openusage.claude.desktopBilling"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: key) }
}
