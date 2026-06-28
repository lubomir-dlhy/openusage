import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Add / edit sheet for a provider account: a label, a config directory (chosen with the native folder
/// picker — config dirs are dotfolders, so hidden files are shown), and an optional custom icon.
/// The parent (`SettingsScreen`) persists the result into `AccountsStore` + `AccountIconStore`.
struct AccountSettingsView: View {
    let providerID: String
    let providerDisplayName: String
    /// nil = adding a new account; non-nil = editing an existing one.
    let existing: ProviderAccount?
    /// Reports the user's choices; the parent does the persistence.
    let onSave: (_ label: String?, _ configDir: String?, _ pickedIconURL: URL?, _ clearIcon: Bool) -> Void
    let onCancel: () -> Void

    @State private var label: String
    @State private var configDir: String
    @State private var pickedIconURL: URL?
    @State private var clearIcon: Bool

    init(
        providerID: String,
        providerDisplayName: String,
        existing: ProviderAccount?,
        onSave: @escaping (_ label: String?, _ configDir: String?, _ pickedIconURL: URL?, _ clearIcon: Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.providerID = providerID
        self.providerDisplayName = providerDisplayName
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        _label = State(initialValue: existing?.label ?? "")
        _configDir = State(initialValue: existing?.configDir ?? "")
        _pickedIconURL = State(initialValue: nil)
        _clearIcon = State(initialValue: false)
    }

    private var envVarName: String { providerID == "codex" ? "CODEX_HOME" : "CLAUDE_CONFIG_DIR" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existing == nil ? "Add \(providerDisplayName) Account" : "Edit \(providerDisplayName) Account")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Label").font(.caption).foregroundStyle(.secondary)
                TextField("e.g. Work", text: $label).textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Config Directory").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(configDir.isEmpty ? "Default location" : configDir)
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(configDir.isEmpty ? Color.secondary : Color.primary)
                    Spacer(minLength: 8)
                    if !configDir.isEmpty { Button("Clear") { configDir = "" }.buttonStyle(.link) }
                    Button("Choose…") { chooseFolder() }
                }
                Text("Sets \(envVarName) for this account. Tip: press ⌘⇧. in the dialog to show hidden folders.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Icon").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    iconPreview.frame(width: 22, height: 22)
                    Spacer(minLength: 8)
                    Button("Choose…") { chooseIcon() }
                    Button("Default") { pickedIconURL = nil; clearIcon = true }
                }
                Text("PNG recommended; rendered monochrome in the menu bar.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(trimmedOrNil(label), trimmedOrNil(configDir), pickedIconURL, clearIcon)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400, height: 320)
    }

    @ViewBuilder private var iconPreview: some View {
        if let url = pickedIconURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit()
        } else if !clearIcon, let fileName = existing?.iconFileName, let image = AccountIconStore.image(named: fileName) {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            ProviderIcon(source: .providerMark(providerID))
        }
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Select the \(providerDisplayName) config directory"
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { configDir = url.path }
    }

    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .bmp, .heic]
        panel.message = "Choose an icon image (PNG recommended)"
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            pickedIconURL = url
            clearIcon = false
        }
    }
}
