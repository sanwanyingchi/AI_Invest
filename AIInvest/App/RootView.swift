import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        } detail: {
            detail
                .frame(minWidth: 860, minHeight: 640)
                .background(AppTheme.canvas)
                .toolbar { toolbarContent }
        }
        .task {
            await appModel.checkLongbridgeConnection()
            await appModel.runDueResearchSchedules()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(900))
                await appModel.runDueResearchSchedules()
            }
        }
    }

    private var sidebar: some View {
        List(selection: $appModel.selectedSection) {
            Section {
                ForEach(AppSection.allCases) { section in
                    HStack(spacing: 11) {
                        Image(systemName: section.systemImage)
                            .frame(width: 20)
                        Text(section.rawValue)
                        Spacer()
                        if badgeCount(for: section) > 0 {
                            Text("\(badgeCount(for: section))")
                                .font(.caption2.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.08), in: Capsule())
                        }
                    }
                    .padding(.vertical, 5)
                    .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("AI Invest")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(dataStatusColor)
                            .frame(width: 7, height: 7)
                        Text(appModel.dataMode.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    SettingsLink {
                        Label("设置", systemImage: "gearshape")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
            }
            .background(.bar)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch appModel.selectedSection ?? .holdings {
        case .holdings:
            HoldingsView()
        case .strategy:
            StrategyView()
        case .advice:
            AdviceView()
        case .research:
            ResearchView()
        case .learning:
            LearningView()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if case .syncing = appModel.syncState {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task { await appModel.refresh() }
            } label: {
                Label("同步", systemImage: "arrow.clockwise")
            }
            .help(appModel.dataMode == .live ? "同步长桥持仓与行情" : "刷新模拟数据")
            .disabled(appModel.syncState == .syncing)
        }
    }

    private var dataStatusColor: Color {
        if appModel.dataMode == .preview { return AppTheme.warning }
        return appModel.longbridgeConnectionState.isConnected
            ? AppTheme.positive
            : AppTheme.negative
    }

    private func badgeCount(for section: AppSection) -> Int {
        switch section {
        case .advice: appModel.unreadAdviceCount
        case .research: appModel.unreadReportCount
        case .learning: appModel.reviewLearningUnits.count
        default: 0
        }
    }

}
