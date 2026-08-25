import SwiftUI
import UniformTypeIdentifiers

private enum AdviceScope: String, CaseIterable, Identifiable {
    case pending = "待处理"
    case all = "全部建议"
    case decisions = "决策日志"
    case weekly = "周复盘"

    var id: String { rawValue }
}

struct AdviceView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var scope: AdviceScope = .pending
    @State private var isExportingWeeklyReview = false
    @State private var isConfirmingCodexGeneration = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    eyebrow: "ACTION",
                    title: "建议",
                    subtitle: "每条建议都有触发原因、证据和处理状态。"
                ) {
                    Button {
                        isConfirmingCodexGeneration = true
                    } label: {
                        if appModel.codexGenerationScope == .advice {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Codex 生成建议", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appModel.codexGenerationScope != nil)
                }

                if let message = appModel.codexGenerationMessage {
                    CodexGenerationBanner(
                        message: message,
                        isRunning: appModel.codexGenerationScope != nil
                    )
                }

                Picker("建议范围", selection: $scope) {
                    ForEach(AdviceScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 560)
            }
            .padding(.horizontal, 26)
            .padding(.top, 26)
            .padding(.bottom, 18)

            Divider()

            Group {
                switch scope {
                case .pending, .all:
                    adviceList
                case .decisions:
                    decisionLog
                case .weekly:
                    weeklyReview
                }
            }
        }
        .background(AppTheme.canvas)
        .fileExporter(
            isPresented: $isExportingWeeklyReview,
            document: MarkdownDocument(text: weeklyReviewMarkdown),
            contentType: .plainText,
            defaultFilename: "AI-Invest-周复盘.md"
        ) { _ in }
        .confirmationDialog(
            "使用 Codex 生成新建议？",
            isPresented: $isConfirmingCodexGeneration,
            titleVisibility: .visible
        ) {
            Button("开始生成") {
                Task { await appModel.generateAdviceWithCodex() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("Codex 将读取当前持仓权重、策略、投资论点和最近研报，并实时检索近期公开信息。新的 Codex 待处理建议会替换旧的待处理 Codex 建议，本地风险规则和历史决策仍会保留；不会执行交易。")
        }
    }

    private var adviceList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                HStack {
                    Text(scope == .pending ? "需要你处理" : "全部历史建议")
                        .font(.headline)
                    Spacer()
                    Text("\(visibleAdvice.count) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(visibleAdvice) { item in
                    adviceCard(item)
                }

                if visibleAdvice.isEmpty {
                    ContentUnavailableView(
                        "没有待处理建议",
                        systemImage: "checkmark.circle",
                        description: Text("组合目前没有需要立即处理的事项。")
                    )
                    .frame(minHeight: 280)
                }
            }
            .padding(26)
        }
    }

    private func adviceCard(_ item: AdviceItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: priorityIcon(item.priority))
                    .font(.title3)
                    .foregroundStyle(priorityTint(item.priority))
                    .frame(width: 36, height: 36)
                    .background(priorityTint(item.priority).opacity(0.11), in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.title)
                            .font(.headline)
                        StatusPill(text: "\(item.priority.rawValue)优先级", tint: priorityTint(item.priority))
                        StatusPill(text: item.status.rawValue, tint: statusTint(item.status))
                        if let origin = item.origin {
                            StatusPill(
                                text: origin.rawValue,
                                tint: origin == .codex ? AppTheme.info : .secondary,
                                systemImage: origin == .codex ? "sparkles" : nil
                            )
                        }
                    }
                    Text(item.relatedObject)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("置信度 \(item.confidence)")
                        .font(.caption.weight(.medium))
                    Text(AppFormat.dateTime(item.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(item.summary)
                .font(.body)

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("触发原因")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(item.trigger)
                        .font(.subheadline)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("关键证据")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(item.evidence, id: \.self) { evidence in
                        EvidenceRow(text: evidence)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("反面证据")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(item.counterEvidence)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let sources = item.sources, !sources.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    Text("公开来源")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(sources) { source in
                        if let url = source.linkURL {
                            Link(destination: url) {
                                HStack(alignment: .firstTextBaseline) {
                                    Image(systemName: "link")
                                    Text(source.title)
                                    Spacer()
                                    Text("\(source.publisher) · \(source.publishedAt)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
            }

            if item.status == .pending || item.status == .snoozed {
                Divider()
                HStack {
                    Text("有效期至 \(AppFormat.shortDate(item.validUntil))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("忽略") { appModel.updateAdvice(item, status: .ignored) }
                    Button("稍后提醒") { appModel.updateAdvice(item, status: .snoozed) }
                    Button("接受并记录") { appModel.updateAdvice(item, status: .accepted) }
                        .buttonStyle(.borderedProminent)
                }
            } else if item.status == .accepted {
                Divider()
                HStack {
                    Text("已进入决策日志；完成复核或行动后可关闭。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("标记完成") {
                        appModel.updateAdvice(item, status: .completed)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var decisionLog: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "最近决策", subtitle: "建议状态变化与手动记录都会保留")

                ForEach(appModel.advice.filter { $0.status != .pending }) { item in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "checkmark.seal")
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 30, height: 30)
                            .background(AppTheme.accentSoft, in: Circle())
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title)
                                .font(.headline)
                            Text("状态更新为“\(item.status.rawValue)” · \(item.relatedObject)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(AppFormat.dateTime(item.createdAt))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .cardStyle()
                }
            }
            .padding(26)
        }
    }

    private var weeklyReview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("本周组合复盘")
                            .font(.title2.weight(.semibold))
                        Text(
                            appModel.dataMode == .live
                                ? "基于最近一次长桥快照 · 提交决策前仍需核对"
                                : "模拟草稿 · 连接长桥后将使用真实组合数字"
                        )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("导出 Markdown") { isExportingWeeklyReview = true }
                        .buttonStyle(.borderedProminent)
                }

                VStack(alignment: .leading, spacing: 16) {
                    reviewSection("组合变化", text: portfolioReviewSummary)
                    Divider()
                    reviewSection("风险与策略", text: riskReviewSummary)
                    Divider()
                    reviewSection("研究变化", text: researchReviewSummary)
                    Divider()
                    reviewSection("下周行动", text: actionReviewSummary)
                }
                .cardStyle()
            }
            .padding(26)
        }
    }

    private var visibleAdvice: [AdviceItem] {
        switch scope {
        case .pending:
            appModel.advice.filter { $0.status == .pending || $0.status == .snoozed }
        default:
            appModel.advice
        }
    }

    private var portfolioReviewSummary: String {
        let largestSector = appModel.sectorAllocations.first.map {
            let percent = appModel.portfolio.totalAssets == 0
                ? 0
                : $0.marketValue / appModel.portfolio.totalAssets * 100
            return "最大行业为\($0.sector)，权重约 \(AppFormat.percent(percent))"
        } ?? "当前没有持仓"
        return "总资产 \(AppFormat.money(appModel.portfolio.totalAssets, currency: appModel.portfolio.currency))；当日估算盈亏 \(AppFormat.money(appModel.portfolio.dailyProfit, currency: appModel.portfolio.currency))；\(largestSector)。"
    }

    private var riskReviewSummary: String {
        let attention = appModel.evaluatedStrategyRules.filter { $0.state != .healthy }
        guard !attention.isEmpty else {
            return "当前策略规则均在设定范围内，纪律分为 \(appModel.disciplineScore) / 100。"
        }
        return attention.map { "\($0.title)：\($0.currentValue)，边界 \($0.limitValue)" }
            .joined(separator: "；")
    }

    private var researchReviewSummary: String {
        guard let report = appModel.reports.max(by: { $0.generatedAt < $1.generatedAt }) else {
            return "本周还没有行业研报；可先在行业研报页运行一个任务。"
        }
        return "最近研报《\(report.title)》：\(report.executiveSummary)"
    }

    private var actionReviewSummary: String {
        let pending = appModel.advice
            .filter { $0.status == .pending || $0.status == .snoozed }
            .prefix(3)
            .enumerated()
            .map { "\($0.offset + 1). \($0.element.title)" }
        return pending.isEmpty ? "当前没有待处理事项；继续按计划复盘，不因短期波动临时交易。" : pending.joined(separator: "\n")
    }

    private func reviewSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var weeklyReviewMarkdown: String {
        let largest = appModel.largestHolding.map {
            "\($0.name)（\($0.symbol)）权重 \(AppFormat.percent(appModel.portfolioWeight(for: $0) * 100))"
        } ?? "暂无持仓"
        let pending = appModel.advice
            .filter { $0.status == .pending || $0.status == .snoozed }
            .map { "- \($0.title)：\($0.summary)" }
            .joined(separator: "\n")

        return """
        # AI Invest｜本周组合复盘

        - 生成时间：\(AppFormat.dateTime(.now))
        - 数据模式：\(appModel.dataMode.rawValue)
        - 基础币种：\(appModel.portfolio.currency)

        ## 组合快照

        - 总资产：\(AppFormat.money(appModel.portfolio.totalAssets, currency: appModel.portfolio.currency))
        - 现金缓冲：\(AppFormat.percent(appModel.portfolio.cashWeight * 100))
        - 最大持仓：\(largest)
        - 纪律分：\(appModel.disciplineScore) / 100

        ## 本周待处理事项

        \(pending.isEmpty ? "- 当前没有待处理建议。" : pending)

        ## 复盘提醒

        - 哪些判断被新证据支持，哪些需要推翻？
        - 当前配置是否仍符合生活现金需求与风险承受能力？
        - 下周只保留最重要的 1–3 个行动，不因短期波动临时交易。

        > 本文是个人研究与复盘材料，不构成投资建议，也不会触发交易。
        """
    }

    private func priorityTint(_ priority: AdvicePriority) -> Color {
        switch priority {
        case .high: AppTheme.negative
        case .medium: AppTheme.warning
        case .low: AppTheme.info
        }
    }

    private func priorityIcon(_ priority: AdvicePriority) -> String {
        switch priority {
        case .high: "exclamationmark.triangle.fill"
        case .medium: "exclamationmark.circle.fill"
        case .low: "info.circle.fill"
        }
    }

    private func statusTint(_ status: AdviceStatus) -> Color {
        switch status {
        case .pending: AppTheme.warning
        case .accepted: AppTheme.info
        case .snoozed: .secondary
        case .completed: AppTheme.positive
        case .ignored: .secondary
        }
    }
}

private struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(data: data, encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
