import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var keyDraft = ""

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    if settings.hasAPIKey {
                        Label("API key saved in the Keychain", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Button("Remove key", role: .destructive) { settings.removeAPIKey() }
                    } else {
                        SecureField("sk-ant-…", text: $keyDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.password)
                        Button("Save key") {
                            settings.saveAPIKey(keyDraft)
                            keyDraft = ""
                        }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text("Claude API key")
                } footer: {
                    Text("Noluma uses your own Claude API key to build apps. Create one at platform.claude.com. The key is stored in this iPhone's Keychain and is only ever sent to Anthropic.")
                }

                Section {
                    Picker("Model", selection: $settings.model) {
                        ForEach(ModelOption.all) { option in
                            VStack(alignment: .leading) {
                                Text(option.name)
                                Text(option.note).font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(option.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Model")
                }

                Section {
                    TextField("You", text: $settings.displayName)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Name shown on apps you publish")
                }

                Section {
                    privacyRow("bubble.left.and.text.bubble.right.fill", "Your chat messages are sent to Anthropic's Claude API to build your apps. Nothing else leaves this iPhone.")
                    privacyRow("wifi.slash", "Apps you build or download run in a sandbox with no internet access.")
                    privacyRow("internaldrive.fill", "Each app's data is stored on this iPhone, separate from every other app.")
                    privacyRow("globe", "An app is only shared when you publish it. Publishing shares its code, never your data.")
                } header: {
                    Text("Privacy")
                }

                if settings.usesMockAI {
                    Section {
                        Label("Demo mode: replies are scripted and no network is used.", systemImage: "theatermasks.fill")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func privacyRow(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: icon).foregroundStyle(.tint)
        }
    }
}
