import AppKit
import AutoInputSwitcherCore
import SwiftUI

struct MainWindowView: View {
    @ObservedObject var runtime: AppRuntime
    @State private var loadedIcons: [String: NSImage] = [:]
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topBar
            voiceBar
            filterBar
            applicationsContent
        }
        .padding(18)
        .frame(minWidth: 960, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: runtime.iconCacheGeneration) { _, _ in
            // Icons are cached by path and the scan invalidates them in one step.
            loadedIcons.removeAll()
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "keyboard")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("AutoInputSwitcher")
                    .font(.system(.title3, design: .default, weight: .semibold))
                Text("按应用自动切换输入法")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 24)

            metric(title: "已切换", value: "\(runtime.switchCount)")
            metric(title: "已配置", value: "\(runtime.configuredRuleCount)")

            Toggle(
                "开机自启",
                isOn: Binding(
                    get: { runtime.isLaunchAtLoginEnabled },
                    set: { runtime.setLaunchAtLoginEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .accessibilityLabel("开机自启")

            Toggle("菜单栏图标", isOn: $runtime.showMenuBarIcon)
                .toggleStyle(.switch)
                .accessibilityLabel("显示菜单栏图标")

            Button {
                runtime.refreshApplications()
            } label: {
                Label("刷新应用", systemImage: "arrow.clockwise")
            }
            .disabled(runtime.isScanning)
            .accessibilityLabel("刷新应用列表")

            Button {
                runtime.reloadInputSources()
            } label: {
                Label("刷新输入法", systemImage: "keyboard")
            }
            .accessibilityLabel("刷新输入法列表")

            if let updateController = runtime.updateController {
                CheckForUpdatesButton(controller: updateController)
            }

            Button(role: .destructive) {
                onQuit()
            } label: {
                Label("退出", systemImage: "power")
            }
            .accessibilityLabel("退出 AutoInputSwitcher")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private var voiceBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Toggle("语音输入后切回原输入法", isOn: $runtime.voiceRestoreEnabled)
                .toggleStyle(.switch)
                .accessibilityLabel("语音输入后切回原输入法")

            Picker("语音输入法", selection: $runtime.voiceInputSourceSelection) {
                Text(automaticVoiceChoiceTitle).tag(AppRuntime.automaticVoiceInputSourceID)
                ForEach(runtime.voiceInputSourceChoices) { choice in
                    Text(choice.name).tag(choice.id)
                }
            }
            .frame(width: 300)
            .disabled(!runtime.voiceRestoreEnabled)
            .accessibilityLabel("语音输入法")

            if runtime.voiceRestoreEnabled && runtime.effectiveVoiceInputSource == nil {
                Text("未找到豆包输入法，请在系统设置中添加，或手动选择语音输入法。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private var automaticVoiceChoiceTitle: String {
        if let detected = runtime.detectedVoiceInputSource {
            return "自动识别（" + detected.name + "）"
        }
        return "自动识别（未找到）"
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            TextField("搜索应用或 Bundle ID", text: $runtime.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 240, idealWidth: 300, maxWidth: 380)
                .accessibilityLabel("搜索应用或 Bundle ID")

            Picker("显示范围", selection: $runtime.applicationListScope) {
                Text("全部").tag(ApplicationListScope.all)
                Text("已配置").tag(ApplicationListScope.configured)
                Text("未配置").tag(ApplicationListScope.unconfigured)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .accessibilityLabel("应用显示范围")

            Spacer(minLength: 12)

            statusArea
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private var statusArea: some View {
        HStack(spacing: 8) {
            Text(runtime.statusText)
                .font(.caption)
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .truncationMode(.middle)
                .monospacedDigit()
                .accessibilityLabel(runtime.statusText)

            if runtime.hasStorageFailure {
                Button("重新读取") {
                    runtime.reloadRulesFromDisk()
                }
                .controlSize(.small)

                Button("在 Finder 中显示规则文件") {
                    runtime.revealRulesFileInFinder()
                }
                .controlSize(.small)
            } else if runtime.scanStatus != nil {
                Button("重试") {
                    runtime.refreshApplications()
                }
                .controlSize(.small)
                .disabled(runtime.isScanning)
            }

            if runtime.launchAtLoginStatus == .requiresApproval {
                Button("打开系统设置") {
                    runtime.openLoginItemsSystemSettings()
                }
                .controlSize(.small)
            }
        }
    }

    private var applicationsContent: some View {
        Group {
            if runtime.isScanning && runtime.installedApplications.isEmpty {
                VStack(spacing: 12) {
                    ProgressView("正在扫描已安装应用...")
                    Text("首次加载可能需要几秒钟")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if runtime.filteredInstalledApplications.isEmpty {
                ContentUnavailableView(
                    "没有匹配的应用",
                    systemImage: "magnifyingglass",
                    description: Text("调整搜索内容或切换到“全部”。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                applicationsList
            }
        }
        .frame(minHeight: 470)
    }

    private var applicationsList: some View {
        Table(runtime.filteredInstalledApplications) {
            TableColumn("应用") { application in
                HStack(spacing: 8) {
                    applicationIcon(for: application)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(application.name)
                            .font(.system(size: 13, weight: .medium))

                        if let url = application.url {
                            Text(url.deletingLastPathComponent().path)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        } else {
                            Text("未找到应用")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .width(min: 260, ideal: 320)

            TableColumn("Bundle ID") { application in
                Text(application.bundleIdentifier)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 260, ideal: 340)

            TableColumn("输入法") { application in
                Picker(
                    "",
                    selection: Binding(
                        get: { runtime.selectedInputSourceID(for: application) },
                        set: { runtime.setInputSourceID($0, for: application) }
                    )
                ) {
                    Text("-").tag(AppRuntime.noSwitchInputSourceID)
                    ForEach(runtime.inputSourceChoices(for: application)) { choice in
                        Text(choice.name).tag(choice.id)
                    }
                }
                .labelsHidden()
                .frame(width: 230)
                .disabled(!runtime.ruleEditingEnabled)
                .accessibilityLabel("\(application.name) 的输入法")
            }
            .width(250)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func applicationIcon(for application: InstalledApplication) -> some View {
        if let url = application.url {
            if let icon = loadedIcons[url.path] {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                    .onAppear { loadIcon(for: url) }
            }
        } else {
            Image(systemName: "questionmark.app.dashed")
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private var statusColor: Color {
        switch runtime.primaryStatus?.severity {
        case .error:
            return .red
        case .warning:
            return .orange
        case .info, .none:
            return .secondary
        }
    }

    private func loadIcon(for url: URL) {
        guard loadedIcons[url.path] == nil else {
            return
        }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 24, height: 24)
        loadedIcons[url.path] = icon
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 58, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(value)")
    }
}

/// Separate view so the update button observes the updater state directly.
private struct CheckForUpdatesButton: View {
    @ObservedObject var controller: UpdateController

    var body: some View {
        Button {
            controller.checkForUpdates()
        } label: {
            Label("检查更新…", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(!controller.canCheckForUpdates)
        .accessibilityLabel("检查更新")
    }
}
