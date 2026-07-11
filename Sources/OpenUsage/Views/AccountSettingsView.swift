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
    let onSave: (_ label: String?, _ configDir: String?, _ colorHex: String?, _ pickedIconURL: URL?, _ clearIcon: Bool) -> Void
    let onCancel: () -> Void

    @State private var label: String
    @State private var configDir: String
    @State private var colorHex: String?
    @State private var pickedIconURL: URL?
    @State private var clearIcon: Bool

    /// Preset chart tints offered as swatches (system accent hues); "Automatic" clears the override.
    private static let colorPresets: [String] = [
        "DE7356", "FF9F0A", "FFD60A", "34C759", "30B0C7", "0A84FF", "5856D6", "A855F7", "FF2D55", "A2845E"
    ]

    init(
        providerID: String,
        providerDisplayName: String,
        existing: ProviderAccount?,
        onSave: @escaping (_ label: String?, _ configDir: String?, _ colorHex: String?, _ pickedIconURL: URL?, _ clearIcon: Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.providerID = providerID
        self.providerDisplayName = providerDisplayName
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        _label = State(initialValue: existing?.label ?? "")
        _configDir = State(initialValue: existing?.configDir ?? "")
        _colorHex = State(initialValue: existing?.colorHex)
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Chart Color").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    // "Automatic": the provider's brand color / stable fallback hue.
                    swatch(hex: nil)
                    ForEach(Self.colorPresets, id: \.self) { preset in
                        swatch(hex: preset)
                    }
                }
                Text("Used for this account in the Total Spend chart.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(trimmedOrNil(label), trimmedOrNil(configDir), colorHex, pickedIconURL, clearIcon)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400, height: 390)
    }

    /// One selectable color swatch; `nil` is the "Automatic" slot showing the account's current
    /// automatic tint with a slash to read as "no override".
    private func swatch(hex: String?) -> some View {
        let isSelected = colorHex == hex
        let fill = hex.flatMap(TotalSpendPalette.parseHex)
            ?? TotalSpendPalette.color(for: existing?.id ?? providerID)
        return Button {
            colorHex = hex
        } label: {
            ZStack {
                Circle().fill(fill).frame(width: 18, height: 18)
                if hex == nil {
                    // The "Automatic" slot: a diagonal slash over the automatic tint.
                    Rectangle().fill(.background).frame(width: 2, height: 18).rotationEffect(.degrees(45))
                }
            }
            .overlay(
                Circle().strokeBorder(isSelected ? Color.primary : .clear, lineWidth: 2)
                    .frame(width: 24, height: 24)
            )
            .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hex == nil ? "Automatic color" : "Color \(hex!)")
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
        // Suspend the menu-bar panel's outside-click dismissal so it stays open behind the picker.
        let response = MenuBarPopover.withDismissalSuspended { panel.runModal() }
        if response == .OK, let url = panel.url { configDir = url.path }
    }

    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .bmp, .heic]
        panel.message = "Choose an icon image (PNG recommended)"
        panel.prompt = "Choose"
        // Suspend the menu-bar panel's outside-click dismissal so it stays open behind the picker.
        let response = MenuBarPopover.withDismissalSuspended { panel.runModal() }
        if response == .OK, let url = panel.url {
            pickedIconURL = url
            clearIcon = false
        }
    }
}
