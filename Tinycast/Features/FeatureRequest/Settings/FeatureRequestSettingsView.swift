import AppKit
import SwiftUI

struct FeatureRequestSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(FeatureRequestSettingsStore.self) private var store

    var body: some View {
        @Bindable var settings = settings
        @Bindable var store = store
        return Form {
            Section {
                Toggle(isOn: $settings.featureRequestEnabled) {
                    SettingsRowTitle(.featureRequestFeatureRequest, "Enable Request a Feature")
                    Text(
                        "Describe a feature and an agent builds it in a throwaway worktree, runs "
                            + "the project's own checks, and opens a pull request once they pass.")
                }
                Text(
                    "The agent runs with every tool enabled and no per-action prompt. It works "
                        + "only inside its own worktree, never your checkout, but it can push a "
                        + "branch and open a pull request on your behalf.")
                .font(.callout)
                .foregroundStyle(.secondary)
            } header: {
                SettingsSectionHeader(.featureRequestFeatureRequest)
            }

            Section {
                SettingsRow(
                    title: "Checkout", subtitle: subtitle, anchor: .featureRequestRepository
                ) {
                    Button("Choose…", action: chooseRepository)
                }
                LabeledContent {
                    TextField("", text: $store.baseBranch)
                        .labelsHidden()
                        .frame(width: 160)
                } label: {
                    SettingsRowTitle(.featureRequestRepository, "Base branch")
                    Text("Branches are cut from this, and pull requests target it.")
                }
            } header: {
                SettingsSectionHeader(.featureRequestRepository)
            }
            .settingsEnabled(settings.featureRequestEnabled)

            Section {
                Picker(selection: $store.model) {
                    ForEach(FeatureRequestSettingsStore.models) { model in
                        Text(model.name).tag(model.id)
                    }
                } label: {
                    SettingsRowTitle(.featureRequestAgent, "Model")
                    Text("Claude Code has to be installed and signed in.")
                }
                Stepper(value: $store.maxAttempts, in: FeatureRequestSettingsStore.attemptRange) {
                    SettingsRowTitle(.featureRequestAgent, "Attempts")
                    Text(
                        "A failing check goes back to the same session, up to "
                            + "\(store.maxAttempts) time\(store.maxAttempts == 1 ? "" : "s").")
                }
                Toggle(isOn: $store.opensPullRequest) {
                    SettingsRowTitle(.featureRequestAgent, "Open the pull request")
                    Text(
                        "Off pushes the verified branch and stops there, leaving the pull request "
                            + "to you.")
                }
            } header: {
                SettingsSectionHeader(.featureRequestAgent)
            }
            .settingsEnabled(settings.featureRequestEnabled)

            FeatureCommandsSection(owner: .featureRequest, anchor: .featureRequestCommands)
                .settingsEnabled(settings.featureRequestEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.featureRequest)
    }

    /// Says what is wrong rather than only that something is: a wrong folder is the usual mistake.
    private var subtitle: String {
        guard let repository = store.repository else {
            return "Not set — choose the Tinycast checkout to build in."
        }
        guard GitRunner.isTinycastCheckout(repository) else {
            return "\(repository.path) does not look like a Tinycast checkout."
        }
        return repository.path
    }

    private func chooseRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the Tinycast checkout features should be built in."
        // Tinycast is an accessory app, so the panel opens behind the frontmost app without this.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.repositoryPath = url.path
    }
}
