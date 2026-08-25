import Charts
import SwiftUI

private enum ResearchScope: String, CaseIterable, Identifiable {
    case latest = "最新研报"
    case industries = "行业分类"
    case institutions = "机构观点"
    case schedules = "定时任务"
    case history = "运行历史"

    var id: String { rawValue }
}

struct ResearchView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var scope: ResearchScope = .latest
    @State private var isCreatingSchedule = false
    @State private var selectedReport: IndustryReport?
    @State private var deleteScheduleCandidate: ResearchSchedule?
    @State private var latestIndustry = "全部行业"
    @State private var selectedIndustry = "全部行业"

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    eyebrow: "RESEARCH",
                    title: "行业研报",
                    subtitle: "定时整理变化，只把与持仓和论点有关的证据带回来。"
                ) {
                    Button {
                        isCreatingSchedule = true
                    } label: {
                        Label("新建定时任务", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Picker("研究范围", selection: $scope) {
                    ForEach(ResearchScope.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 760)
            }
            .padding(.horizontal, 26)
            .padding(.top, 26)
            .padding(.bottom, 18)

            Divider()

            Group {
                switch scope {
                case .latest: latestReports
                case .industries: industryView
                case .institutions: institutionsView
                case .schedules: schedulesView
                case .history: runHistory
                }
            }
        }
        .background(AppTheme.canvas)
        .sheet(isPresented: $isCreatingSchedule) {
            CreateScheduleSheet()
                .environmentObject(appModel)
        }
        .sheet(item: $selectedReport) { report in
            ReportDetailView(report: report)
        }
        .alert(item: $deleteScheduleCandidate) { schedule in
            Alert(
                title: Text("删除定时任务？"),
                message: Text("“\(schedule.name)”将被删除，已生成的历史研报会保留。"),
                primaryButton: .destructive(Text("删除")) {
                    appModel.deleteSchedule(schedule)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private var latestReports: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if appModel.dataMode == .preview {
                    SimulationBanner()
                }

                if let schedule = appModel.schedules.first {
                    scheduleHighlight(schedule)
                }

                SectionTitle(
                    title: "最近生成",
                    subtitle: "按行业筛选；机构观点仅来自公开官方材料，GPT 摘要不代表机构背书"
                )

                industryFilter(selection: latestIndustry) { latestIndustry = $0 }

                LazyVStack(spacing: 12) {
                    ForEach(latestFilteredReports) { report in
                        Button {
                            selectedReport = report
                            appModel.markReportRead(report)
                        } label: {
                            reportCard(report)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(26)
        }
    }

    private func scheduleHighlight(_ schedule: ResearchSchedule) -> some View {
        HStack(spacing: 18) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 28))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 56, height: 56)
                .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(schedule.name)
                        .font(.headline)
                    StatusPill(
                        text: schedule.isEnabled ? "已启用" : "已暂停",
                        tint: schedule.isEnabled ? AppTheme.positive : .secondary
                    )
                }
                Text("\(schedule.template.rawValue) · \(schedule.industryScope)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("下次运行 \(AppFormat.dateTime(schedule.nextRunAt))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("管理任务") { scope = .schedules }
            Button {
                Task { await appModel.runSchedule(schedule) }
            } label: {
                if appModel.isGeneratingReport {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("立即运行")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appModel.isGeneratingReport)
        }
        .cardStyle()
    }

    private func reportCard(_ report: IndustryReport) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if report.isUnread {
                            Circle()
                                .fill(AppTheme.accent)
                                .frame(width: 7, height: 7)
                        }
                        Text(report.title)
                            .font(.headline)
                    }
                    Text("\(report.industry) · \(AppFormat.shortDate(report.periodStart))–\(AppFormat.shortDate(report.periodEnd))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(text: "GPT 生成", tint: AppTheme.info, systemImage: "sparkles")
            }

            Text(report.executiveSummary)
                .font(.body)
                .foregroundStyle(.primary)

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("本期变化")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(report.changes.prefix(2), id: \.self) { change in
                        EvidenceRow(text: change)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("持仓影响")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(report.portfolioImpact)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Text("来源 \(report.sources.count) 个")
                Text("·")
                Text(report.modelName)
                Spacer()
                Text("生成于 \(AppFormat.dateTime(report.generatedAt))")
                Image(systemName: "chevron.right")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var industryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(
                    title: "研报行业分类",
                    subtitle: "自动按研报所属行业归档，新生成的研报会进入对应分类"
                )

                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        industryCategoryButton(
                            title: "全部行业",
                            reportCount: appModel.reports.count,
                            unreadCount: appModel.reports.filter(\.isUnread).count
                        )

                        Divider()
                            .padding(.vertical, 4)

                        ForEach(reportIndustryGroups) { group in
                            industryCategoryButton(
                                title: group.industry,
                                reportCount: group.reports.count,
                                unreadCount: group.unreadCount
                            )
                        }
                    }
                    .frame(width: 220, alignment: .leading)
                    .cardStyle(padding: 10)

                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(
                            title: selectedIndustry,
                            subtitle: "\(selectedIndustryReports.count) 份研报 · 按生成时间倒序"
                        )

                        if selectedIndustryReports.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.secondary)
                                Text("该行业暂无研报")
                                    .font(.headline)
                                Text("可以为这个行业新建定时任务，或立即运行已有任务。")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 180)
                            .cardStyle()
                        } else {
                            ForEach(selectedIndustryReports) { report in
                                Button {
                                    selectedReport = report
                                    appModel.markReportRead(report)
                                } label: {
                                    reportCard(report)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()
                    .padding(.vertical, 4)

                SectionTitle(title: "组合行业暴露", subtitle: "行业权重使用持仓当前市值确定性计算")

                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        Chart(appModel.sectorAllocations) { allocation in
                            BarMark(
                                x: .value("市值", allocation.marketValue),
                                y: .value("行业", allocation.sector)
                            )
                            .foregroundStyle(AppTheme.accent.gradient)
                            .cornerRadius(4)
                        }
                        .chartXAxis {
                            AxisMarks { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let amount = value.as(Double.self) {
                                        Text(amount.formatted(.number.notation(.compactName)))
                                    }
                                }
                            }
                        }
                        .frame(height: 240)
                    }
                    .frame(maxWidth: .infinity)
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("行业观察")
                            .font(.headline)
                        ForEach(Array(industryObservations.enumerated()), id: \.offset) { _, observation in
                            EvidenceRow(text: observation.text, positive: observation.positive)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }

                SectionTitle(title: "持仓行业列表", subtitle: "持仓暴露与研报归档分开计算，避免把缺少研报误认为没有风险")
                ForEach(appModel.sectorAllocations) { allocation in
                    Button {
                        if reportIndustryGroups.contains(where: { $0.industry == allocation.sector }) {
                            selectedIndustry = allocation.sector
                        }
                    } label: {
                        HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(allocation.sector)
                                .font(.headline)
                            Text("\(appModel.portfolio.holdings.filter { $0.sector == allocation.sector }.count) 个持仓标的")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(AppFormat.money(allocation.marketValue))
                            .font(.headline.monospacedDigit())
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .cardStyle(padding: 14)
                }
            }
            .padding(26)
        }
    }

    private var schedulesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(title: "定时任务", subtitle: "所有任务只读长桥数据，不具备交易权限")
                    Spacer()
                    Button("新建任务") { isCreatingSchedule = true }
                        .buttonStyle(.borderedProminent)
                }

                ForEach(appModel.schedules) { schedule in
                    HStack(spacing: 16) {
                        Image(systemName: schedule.isEnabled ? "calendar.badge.checkmark" : "calendar.badge.minus")
                            .font(.title2)
                            .foregroundStyle(schedule.isEnabled ? AppTheme.accent : .secondary)
                            .frame(width: 44, height: 44)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))

                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(schedule.name)
                                    .font(.headline)
                                StatusPill(text: schedule.state.rawValue, tint: scheduleTint(schedule.state))
                            }
                            Text("\(schedule.industryScope) · \(schedule.template.rawValue)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("定向来源：\(schedule.selectedInstitutionSources.map(\.rawValue).joined(separator: "、"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("下次运行 \(AppFormat.dateTime(schedule.nextRunAt)) · 预算记录 HKD \(AppFormat.number(schedule.monthlyBudget, decimals: 0)) / 月")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        Button(schedule.isEnabled ? "暂停" : "恢复") {
                            appModel.toggleSchedule(schedule)
                        }
                        .disabled(appModel.isGeneratingReport)
                        Button(role: .destructive) {
                            deleteScheduleCandidate = schedule
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("删除任务；历史研报会保留")
                        .disabled(appModel.isGeneratingReport)
                        Button("立即运行") {
                            Task { await appModel.runSchedule(schedule) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appModel.isGeneratingReport)
                    }
                    .cardStyle()
                }
            }
            .padding(26)
        }
    }

    private var institutionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 25))
                        .foregroundStyle(AppTheme.info)
                        .frame(width: 50, height: 50)
                        .background(AppTheme.info.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("华尔街与全球机构公开研究")
                            .font(.headline)
                        Text("“华尔街”不是单一发布方。这里定向跟踪大摩、高盛、摩根大通的公开研究，以及桥水的公开宏观与组合研究。不会绕过登录、订阅或版权限制获取客户专属报告。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(text: "仅官方域名", tint: AppTheme.positive, systemImage: "checkmark.shield")
                }
                .cardStyle()

                SectionTitle(
                    title: "定向研究源",
                    subtitle: "运行 GPT 任务时按行业检索最近 30 天；无相关材料时最多扩大到 90 天并标注日期"
                )

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 14
                ) {
                    ForEach(InstitutionResearchSource.allCases) { source in
                        institutionCard(source)
                    }
                }

                SectionTitle(
                    title: "已引用的机构原文",
                    subtitle: "只统计已保存到研报来源列表、且域名通过白名单校验的链接"
                )

                let references = institutionReferences
                if references.isEmpty {
                    VStack(spacing: 9) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 31))
                            .foregroundStyle(.secondary)
                        Text("还没有采用机构公开材料")
                            .font(.headline)
                        Text("配置 OpenAI API Key 后立即运行一个任务；没有找到官方原文时，报告会明确写证据不足。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 170)
                    .cardStyle()
                } else {
                    ForEach(references, id: \.url) { reference in
                        HStack(spacing: 12) {
                            Image(systemName: "link.circle.fill")
                                .font(.title2)
                                .foregroundStyle(AppTheme.info)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(reference.label)
                                    .font(.subheadline.weight(.medium))
                                Text(reference.reportTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Link("查看原文", destination: reference.url)
                        }
                        .cardStyle(padding: 14)
                    }
                }
            }
            .padding(26)
        }
    }

    private func institutionCard(_ source: InstitutionResearchSource) -> some View {
        let taskCount = appModel.schedules.filter {
            $0.selectedInstitutionSources.contains(source)
        }.count
        let citationCount = institutionReferences.filter {
            $0.url.host?.hasSuffix(source.domain) == true
        }.count

        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.rawValue)
                        .font(.headline)
                    Text(source.organizationKind)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: source == .bridgewater ? "globe.americas.fill" : "building.2.fill")
                    .font(.title2)
                    .foregroundStyle(source == .bridgewater ? AppTheme.warning : AppTheme.info)
            }
            Text(source.focus)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                StatusPill(text: "\(taskCount) 个任务", tint: AppTheme.info)
                StatusPill(text: "\(citationCount) 次引用", tint: citationCount > 0 ? AppTheme.positive : .secondary)
                Spacer()
                Link("打开官方研究页", destination: source.portalURL)
                    .font(.caption.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var institutionReferences: [(url: URL, label: String, reportTitle: String)] {
        var seen = Set<String>()
        return appModel.reports.flatMap { report in
            report.sources.compactMap { source -> (URL, String, String)? in
                guard let link = researchSourceLink(from: source),
                      let host = link.url.host?.lowercased(),
                      InstitutionResearchSource.allCases.contains(where: {
                          host == $0.domain || host.hasSuffix(".\($0.domain)")
                      }),
                      seen.insert(link.url.absoluteString).inserted else { return nil }
                return (link.url, link.label, report.title)
            }
        }
    }

    private func researchSourceLink(from source: String) -> (label: String, url: URL)? {
        guard let range = source.range(of: "https://"),
              let url = URL(string: String(source[range.lowerBound...])) else { return nil }
        let prefix = String(source[..<range.lowerBound])
        let label = prefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "·"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (label.isEmpty ? url.absoluteString : label, url)
    }

    private var runHistory: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "运行历史", subtitle: "保留时间、状态、模型和结果，便于复核与诊断")

                ForEach(appModel.reports) { report in
                    HStack(spacing: 14) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.positive)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(report.title)
                                .font(.headline)
                            Text("\(report.modelName) · \(report.sources.count) 个来源")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(AppFormat.dateTime(report.generatedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("查看") {
                            selectedReport = report
                            appModel.markReportRead(report)
                        }
                    }
                    .cardStyle(padding: 14)
                }
            }
            .padding(26)
        }
    }

    private func scheduleTint(_ state: ScheduleRunState) -> Color {
        switch state {
        case .ready: AppTheme.info
        case .running: AppTheme.warning
        case .succeeded: AppTheme.positive
        case .failed: AppTheme.negative
        case .waitingForData: AppTheme.warning
        }
    }

    private var reportIndustryGroups: [ReportIndustryGroup] {
        Dictionary(grouping: appModel.reports, by: \.industry)
            .map { industry, reports in
                ReportIndustryGroup(
                    industry: industry,
                    reports: reports.sorted { $0.generatedAt > $1.generatedAt }
                )
            }
            .sorted { $0.latestGeneratedAt > $1.latestGeneratedAt }
    }

    private var industryObservations: [(text: String, positive: Bool)] {
        guard let largestSector = appModel.sectorAllocations.first,
              appModel.portfolio.totalAssets > 0 else {
            return [("尚无可用于行业分析的非现金持仓。", true)]
        }

        let sectorWeight = largestSector.marketValue / appModel.portfolio.totalAssets * 100
        let sectorHoldings = appModel.portfolio.holdings.filter {
            $0.assetType != .cash && $0.sector == largestSector.sector
        }
        var observations: [(String, Bool)] = [
            (
                "最大行业为\(largestSector.sector)，占组合 \(AppFormat.percent(sectorWeight))。",
                sectorWeight < 30
            )
        ]

        if let largest = sectorHoldings.max(by: { $0.marketValue < $1.marketValue }) {
            let holdingWeight = appModel.portfolioWeight(for: largest) * 100
            observations.append((
                "\(largestSector.sector)包含 \(sectorHoldings.count) 个标的；其中\(largest.name)占组合 \(AppFormat.percent(holdingWeight))。",
                holdingWeight < 20
            ))
        }

        let unclassifiedCount = appModel.portfolio.holdings.filter {
            $0.assetType != .cash && $0.sector == "待分类"
        }.count
        observations.append(
            unclassifiedCount == 0
                ? ("所有非现金持仓都已完成行业分类。", true)
                : ("仍有 \(unclassifiedCount) 个持仓待分类，行业集中度可能不完整。", false)
        )
        return observations
    }

    private var latestFilteredReports: [IndustryReport] {
        let reports = latestIndustry == "全部行业"
            ? appModel.reports
            : appModel.reports.filter { $0.industry == latestIndustry }
        return reports.sorted { $0.generatedAt > $1.generatedAt }
    }

    private var selectedIndustryReports: [IndustryReport] {
        let reports = selectedIndustry == "全部行业"
            ? appModel.reports
            : appModel.reports.filter { $0.industry == selectedIndustry }
        return reports.sorted { $0.generatedAt > $1.generatedAt }
    }

    private func industryFilter(selection: String, onSelect: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                industryFilterButton(
                    title: "全部行业",
                    count: appModel.reports.count,
                    isSelected: selection == "全部行业",
                    onSelect: onSelect
                )

                ForEach(reportIndustryGroups) { group in
                    industryFilterButton(
                        title: group.industry,
                        count: group.reports.count,
                        isSelected: selection == group.industry,
                        onSelect: onSelect
                    )
                }
            }
        }
    }

    private func industryFilterButton(
        title: String,
        count: Int,
        isSelected: Bool,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        Button {
            onSelect(title)
        } label: {
            HStack(spacing: 6) {
                Text(title)
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white.opacity(0.82) : .secondary)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? AppTheme.accent : Color.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func industryCategoryButton(title: String, reportCount: Int, unreadCount: Int) -> some View {
        let isSelected = selectedIndustry == title
        return Button {
            selectedIndustry = title
        } label: {
            HStack(spacing: 9) {
                Image(systemName: title == "全部行业" ? "square.grid.2x2" : "building.2")
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text("\(reportCount) 份研报")
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.75) : .secondary)
                }
                Spacer()
                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(isSelected ? Color.white.opacity(0.18) : AppTheme.accentSoft, in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isSelected ? AppTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ReportIndustryGroup: Identifiable {
    let industry: String
    let reports: [IndustryReport]

    var id: String { industry }
    var unreadCount: Int { reports.filter(\.isUnread).count }
    var latestGeneratedAt: Date { reports.map(\.generatedAt).max() ?? .distantPast }
}

private struct CreateScheduleSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = "持仓行业周报"
    @State private var industry = "全部持仓行业"
    @State private var template: ReportTemplate = .weekly
    @State private var selectedInstitutions = Set(InstitutionResearchSource.allCases)

    private var industries: [String] {
        ["全部持仓行业"] + Array(Set(appModel.portfolio.holdings.map(\.sector))).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("新建定时行业研报")
                    .font(.title2.weight(.semibold))
                Text("首次创建后建议先立即运行，检查来源与输出质量。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("任务名称", text: $name)
                Picker("行业范围", selection: $industry) {
                    ForEach(industries, id: \.self) { Text($0).tag($0) }
                }
                Picker("研报模板", selection: $template) {
                    ForEach(ReportTemplate.allCases) { template in
                        Text(template.rawValue).tag(template)
                    }
                }
                Section("机构公开研究源") {
                    ForEach(InstitutionResearchSource.allCases) { source in
                        Toggle(isOn: Binding(
                            get: { selectedInstitutions.contains(source) },
                            set: { isSelected in
                                if isSelected {
                                    selectedInstitutions.insert(source)
                                } else {
                                    selectedInstitutions.remove(source)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.rawValue)
                                Text("\(source.organizationKind) · \(source.focus)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("只检索官方公开页面；不会访问付费、客户专属或需要登录的研报。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent(
                    "默认预算",
                    value: "HKD \(appModel.monthlyAIBudget.formatted(.number.precision(.fractionLength(0)))) / 月"
                )
                LabeledContent("权限", value: "只读 · 不执行交易")
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("创建并启用") {
                    appModel.addSchedule(
                        name: name,
                        industryScope: industry,
                        template: template,
                        institutionSources: InstitutionResearchSource.allCases.filter {
                            selectedInstitutions.contains($0)
                        }
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || selectedInstitutions.isEmpty
                )
            }
        }
        .padding(24)
        .frame(width: 560, height: 650)
    }
}

private struct ReportDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let report: IndustryReport

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.title)
                        .font(.title2.weight(.semibold))
                    Text("GPT 生成的个人研究材料 · \(AppFormat.dateTime(report.generatedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(22)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("执行摘要")
                            .font(.headline)
                        Text(report.executiveSummary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("本期变化")
                            .font(.headline)
                        ForEach(report.changes, id: \.self) { EvidenceRow(text: $0) }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("对持仓的影响")
                            .font(.headline)
                        Text(report.portfolioImpact)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("反面证据与限制")
                            .font(.headline)
                        EvidenceRow(text: report.counterEvidence, positive: false)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("来源")
                            .font(.headline)
                        ForEach(report.sources, id: \.self) { source in
                            if let link = sourceLink(from: source) {
                                Link(destination: link.url) {
                                    Label(link.label, systemImage: "link")
                                        .font(.subheadline)
                                }
                            } else {
                                Label(source, systemImage: "doc.text")
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
        }
        .frame(width: 720, height: 680)
    }

    private func sourceLink(from source: String) -> (label: String, url: URL)? {
        guard let range = source.range(of: "https://"),
              let url = URL(string: String(source[range.lowerBound...])) else { return nil }
        let prefix = String(source[..<range.lowerBound])
        let label = prefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "·"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (label.isEmpty ? url.absoluteString : label, url)
    }
}
