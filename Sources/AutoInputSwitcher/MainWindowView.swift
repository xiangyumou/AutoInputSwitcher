import AppKit
import AutoInputSwitcherCore
import SwiftUI

struct MainWindowView: View {
    @ObservedObject var runtime: AppRuntime
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topBar
            filterBar
            applicationsContent
        }
        .padding(18)
        .frame(minWidth: 960, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
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
                    get: { runtime.launchAtLoginEnabled },
                    set: { runtime.setLaunchAtLoginEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .accessibilityLabel("开机自启")

            Button {
                runtime.reloadApplications()
            } label: {
                Label("刷新应用", systemImage: "arrow.clockwise")
            }
            .accessibilityLabel("刷新应用列表")

            Button {
                runtime.reloadInputSources()
            } label: {
                Label("刷新输入法", systemImage: "keyboard")
            }
            .accessibilityLabel("刷新输入法列表")

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

    private var filterBar: some View {
        HStack(spacing: 12) {
            TextField("搜索应用或 Bundle ID", text: $runtime.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 280, idealWidth: 360, maxWidth: 420)
                .accessibilityLabel("搜索应用或 Bundle ID")

            Picker("显示范围", selection: $runtime.applicationListScope) {
                Text("全部").tag(ApplicationListScope.all)
                Text("已配置").tag(ApplicationListScope.configured)
                Text("未配置").tag(ApplicationListScope.unconfigured)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .accessibilityLabel("应用显示范围")

            Spacer()

            Text(statusText)
                .font(.caption)
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .monospacedDigit()
                .accessibilityLabel(statusText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private var applicationsContent: some View {
        Group {
            if runtime.filteredInstalledApplications.isEmpty {
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
                    Image(nsImage: application.icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(application.name)
                            .font(.system(size: 13, weight: .medium))
                        Text(application.url.deletingLastPathComponent().path)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
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
                    ForEach(runtime.inputSources) { source in
                        Text(source.name).tag(source.id)
                    }
                }
                .labelsHidden()
                .frame(width: 230)
                .accessibilityLabel("\(application.name) 的输入法")
            }
            .width(250)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statusText: String {
        if !runtime.statusMessage.isEmpty {
            return runtime.statusMessage
        }

        return "显示 \(runtime.filteredInstalledApplications.count) 个应用"
    }

    private var statusColor: Color {
        runtime.statusMessage.contains("失败") ? .red : .secondary
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
