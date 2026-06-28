import Foundation
import Testing
@testable import OpenUsage

@MainActor
struct AccountsStoreTests {
    private func freshStore() -> AccountsStore {
        let defaults = UserDefaults(suiteName: "AccountsStoreTests-\(UUID().uuidString)")!
        return AccountsStore(defaults: defaults)
    }

    @Test func synthesizesDefaultAccountWhenEmpty() {
        let store = freshStore()
        let accounts = store.accounts(for: "claude")
        #expect(accounts.count == 1)
        #expect(accounts[0].id == "claude")
        #expect(accounts[0].isDefault)
        #expect(accounts[0].configDir == nil)
    }

    @Test func addAppendsExtraAfterDefault() {
        let store = freshStore()
        let added = store.addAccount(providerID: "claude", label: "Work", configDir: "~/CP/.claude")
        #expect(added.id == "claude#1")
        #expect(!added.isDefault)

        let accounts = store.accounts(for: "claude")
        #expect(accounts.count == 2)
        #expect(accounts[0].id == "claude")        // default first
        #expect(accounts[1].id == "claude#1")      // extra second
        #expect(accounts[1].label == "Work")
        #expect(accounts[1].configDir == "~/CP/.claude")
    }

    @Test func allocatesSequentialIDs() {
        let store = freshStore()
        let a = store.addAccount(providerID: "codex", label: "A", configDir: nil)
        let b = store.addAccount(providerID: "codex", label: "B", configDir: nil)
        #expect(a.id == "codex#1")
        #expect(b.id == "codex#2")
    }

    @Test func persistsAcrossInstances() {
        let defaults = UserDefaults(suiteName: "AccountsStoreTests-\(UUID().uuidString)")!
        let first = AccountsStore(defaults: defaults)
        first.addAccount(providerID: "codex", label: "Personal", configDir: "~/.codex")

        let second = AccountsStore(defaults: defaults)
        let accounts = second.accounts(for: "codex")
        #expect(accounts.count == 2)
        #expect(accounts[1].label == "Personal")
    }

    @Test func removeDropsExtraButKeepsDefault() {
        let store = freshStore()
        let added = store.addAccount(providerID: "claude", label: "Work", configDir: nil)
        store.removeAccount(id: added.id)
        #expect(store.accounts(for: "claude").count == 1)
        #expect(store.accounts(for: "claude")[0].isDefault)
    }

    @Test func accountByIDResolvesDefaultAndExtra() {
        let store = freshStore()
        let added = store.addAccount(providerID: "claude", label: "Work", configDir: nil)
        #expect(store.account(id: "claude")?.isDefault == true)
        #expect(store.account(id: added.id)?.label == "Work")
        #expect(store.account(id: "codex")?.isDefault == true) // implicit default for any provider id
    }

    @Test func displayNameUsesLabel() {
        #expect(ProviderAccount.makeDefault(providerID: "claude").displayName(providerDisplayName: "Claude") == "Claude")
        let work = ProviderAccount(id: "claude#1", providerID: "claude", label: "Work", configDir: nil, iconFileName: nil)
        #expect(work.displayName(providerDisplayName: "Claude") == "Claude · Work")
    }

    @Test func blankLabelAndConfigDirNormalizeToNil() {
        let store = freshStore()
        let added = store.addAccount(providerID: "claude", label: "   ", configDir: "")
        #expect(added.label == nil)
        #expect(added.configDir == nil)
    }
}
