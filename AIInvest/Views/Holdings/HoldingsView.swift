import Charts
import SwiftUI

struct HoldingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var editorContext: HoldingEditorContext?
    @State private var classificationHolding: Holding?
    @State private var deleteCandidate: Holding?
    @State private var isRecordingTrade = false

    private let metricColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    eyebrow: "PORTFOLIO",
                    title: "持仓",
                    subtitle: "先看清组合，再决定是否需要行动。"
                ) {
                    HStack(spacing: 14) {
                        VStack(alignment: .trailing, spacing: 5) {
                            Text("数据更新")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(AppFormat.dateTime(appModel.portfolio.updatedAt))
                                .font(.subheadline.weight(.medium))
                        }

                        Button {
                            isRecordingTrade = true
                        } label: {
                            Label("记录交易", systemImage: "list.bullet.clipboard")
                        }
                        .buttonStyle(.bordered)
                        .disabled(appModel.portfolio.holdings.isEmpty)

                        Button {
                            editorContext = HoldingEditorContext(holding: nil)
                        } label: {
                            Label("录入持仓", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if appModel.dataMode == .preview {
                    SimulationBanner()
                } else {
                    LiveDataBanner(syncState: appModel.syncState)
                }

                metrics

                HStack(alignment: .top, spacing: 14) {
                    allocationCard
                    contributionCard
                    riskCard
                }

                holdingsTable
                tradeLedger
            }
            .padding(26)
        }
        .background(AppTheme.canvas)
        .sheet(item: $editorContext) { context in
            HoldingEditorSheet(
                holding: context.holding,
                baseCurrency: appModel.portfolio.currency
            ) { holding in
                appModel.saveManualHolding(holding)
            }
        }
        .sheet(item: $classificationHolding) { holding in
            HoldingClassificationSheet(holding: holding) { sector, note in
                appModel.updateSyncedHoldingMetadata(holding, sector: sector, note: note)
            }
        }
        .sheet(isPresented: $isRecordingTrade) {
            TradeEditorSheet(
                holdings: appModel.portfolio.holdings,
                baseCurrency: appModel.portfolio.currency
            ) { trade, applyToPosition, applyToCash in
                appModel.recordTrade(
                    trade,
                    applyToPosition: applyToPosition,
                    applyToCash: applyToCash
                ) ? nil : (appModel.lastPersistenceError ?? "交易记录保存失败。")
            }
        }
        .alert(item: $deleteCandidate) { holding in
            Alert(
                title: Text("删除手动持仓？"),
                message: Text("“\(holding.name)”将从本机组合中移除，此操作无法撤销。"),
                primaryButton: .destructive(Text("删除")) {
                    appModel.deleteManualHolding(holding)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: metricColumns, spacing: 12) {
            MetricCard(
                title: "总资产",
                value: AppFormat.money(
                    appModel.portfolio.totalAssets,
                    currency: appModel.portfolio.currency
                ),
                detail: "持仓 + 现金",
                tint: AppTheme.info,
                systemImage: "banknote"
            )

            MetricCard(
                title: "当日估算盈亏",
                value: AppFormat.money(
                    appModel.portfolio.dailyProfit,
                    currency: appModel.portfolio.currency,
                    decimals: 0
                ),
                detail: AppFormat.percent(dailyProfitPercent, signed: true),
                tint: .performance(appModel.portfolio.dailyProfit),
                systemImage: appModel.portfolio.dailyProfit >= 0 ? "arrow.up.right" : "arrow.down.right"
            )

            MetricCard(
                title: "持仓累计盈亏",
                value: AppFormat.money(
                    appModel.portfolio.totalProfit,
                    currency: appModel.portfolio.currency
                ),
                detail: AppFormat.percent(totalProfitPercent, signed: true),
                tint: .performance(appModel.portfolio.totalProfit),
                systemImage: "chart.line.uptrend.xyaxis"
            )

            MetricCard(
                title: "现金缓冲",
                value: AppFormat.money(
                    appModel.portfolio.totalCash,
                    currency: appModel.portfolio.currency
                ),
                detail: "占组合 \(AppFormat.percent(appModel.portfolio.cashWeight * 100))",
                tint: AppTheme.accent,
                systemImage: "shield.lefthalf.filled"
            )
        }
    }

    private var allocationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "行业配置", subtitle: "按当前市值估算")

            Chart(appModel.sectorAllocations) { allocation in
                SectorMark(
                    angle: .value("市值", allocation.marketValue),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .cornerRadius(3)
                .foregroundStyle(by: .value("行业", allocation.sector))
            }
            .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
            .frame(height: 180)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var contributionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "当日贡献", subtitle: "按同步或录入的涨跌估算")

            Chart(sortedContributors) { holding in
                BarMark(
                    x: .value("盈亏", holding.estimatedDailyProfit),
                    y: .value("标的", holding.name)
                )
                .foregroundStyle(Color.performance(holding.estimatedDailyProfit))
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(position: .bottom) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(amount.formatted(.number.notation(.compactName)))
                        }
                    }
                }
            }
            .frame(height: 180)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var riskCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle(title: "组合体检", subtitle: "规则优先于情绪")
                Spacer()
                StatusPill(
                    text: attentionRules.isEmpty ? "全部正常" : "\(attentionRules.count) 项需复核",
                    tint: attentionRules.contains { $0.state == .breached } ? AppTheme.negative : (attentionRules.isEmpty ? AppTheme.positive : AppTheme.warning),
                    systemImage: attentionRules.isEmpty ? "checkmark.circle.fill" : "exclamationmark"
                )
            }

            if attentionRules.isEmpty {
                EvidenceRow(text: "集中度与现金缓冲均在当前策略范围内。")
            } else {
                ForEach(attentionRules.prefix(2)) { rule in
                    EvidenceRow(
                        text: "\(rule.title)：当前 \(rule.currentValue)，策略边界 \(rule.limitValue)。",
                        positive: false
                    )
                }
            }
            if let cashRule = appModel.evaluatedStrategyRules.first(where: { $0.id == "cash-buffer" }),
               cashRule.state == .healthy {
                EvidenceRow(
                    text: "现金缓冲 \(cashRule.currentValue)，符合 \(cashRule.limitValue) 要求。"
                )
            }
            EvidenceRow(text: "当前本地账本未记录杠杆、卖空或复杂产品暴露。")

            Divider()

            Button {
                appModel.selectedSection = .advice
            } label: {
                HStack {
                    Text("查看相关建议")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var holdingsTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(
                title: "当前持仓",
                subtitle: "\(appModel.portfolio.holdings.count) 项资产 · \(appModel.manualHoldingCount) 项手动录入 · 基础币种 \(appModel.portfolio.currency)"
            )

            Table(appModel.portfolio.holdings) {
                TableColumn("标的") { holding in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(holding.name)
                            .fontWeight(.medium)
                        Text(holding.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 140, ideal: 180)

                TableColumn("类型") { holding in
                    Label(holding.assetType.rawValue, systemImage: holding.assetType.systemImage)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 100)

                TableColumn("来源") { holding in
                    StatusPill(
                        text: holding.source == .manual ? "手动" : "长桥",
                        tint: holding.source == .manual ? AppTheme.warning : AppTheme.info,
                        systemImage: holding.source == .manual ? "pencil" : "arrow.triangle.2.circlepath"
                    )
                    .help(
                        holding.source == .manual
                            ? "手动更新于 \(AppFormat.dateTime(holding.updatedAt))"
                            : "由长桥账户同步"
                    )
                }
                .width(min: 76, ideal: 88)

                TableColumn("现价") { holding in
                    Text(AppFormat.money(holding.lastPrice, currency: holding.currency, decimals: 2))
                        .monospacedDigit()
                }
                .width(min: 115, ideal: 135)

                TableColumn("今日") { holding in
                    Text(AppFormat.percent(holding.dailyChangePercent, signed: true))
                        .monospacedDigit()
                        .foregroundStyle(Color.performance(holding.dailyChangePercent))
                }
                .width(min: 70, ideal: 80)

                TableColumn("持仓") { holding in
                    Text(AppFormat.quantity(holding.shares))
                        .monospacedDigit()
                }
                .width(min: 70, ideal: 90)

                TableColumn("市值") { holding in
                    Text(AppFormat.money(holding.marketValue, currency: appModel.portfolio.currency))
                        .monospacedDigit()
                }
                .width(min: 115, ideal: 130)

                TableColumn("累计盈亏") { holding in
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(AppFormat.money(holding.totalProfit, currency: appModel.portfolio.currency))
                        Text(AppFormat.percent(holding.totalProfitPercent, signed: true))
                            .font(.caption)
                    }
                    .monospacedDigit()
                    .foregroundStyle(Color.performance(holding.totalProfit))
                }
                .width(min: 120, ideal: 140)

                TableColumn("权重") { holding in
                    Text(AppFormat.percent(appModel.portfolioWeight(for: holding) * 100))
                        .monospacedDigit()
                }
                .width(min: 65, ideal: 75)

                TableColumn("") { holding in
                    Menu {
                        if holding.source == .manual {
                            Button {
                                editorContext = HoldingEditorContext(holding: holding)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }

                            Divider()

                            Button(role: .destructive) {
                                deleteCandidate = holding
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        } else {
                            Button {
                                classificationHolding = holding
                            } label: {
                                Label("设置行业", systemImage: "tag")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .help(holding.source == .manual ? "管理手动持仓" : "设置本地行业分类")
                }
                .width(36)
            }
            .frame(height: 340)
        }
        .cardStyle()
    }

    private var totalProfitPercent: Double {
        appModel.portfolio.totalCost == 0 ? 0 : appModel.portfolio.totalProfit / appModel.portfolio.totalCost * 100
    }

    private var tradeLedger: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(
                title: "本地交易记录",
                subtitle: "仅用于记账和复盘，不会向任何券商发送订单",
                actionTitle: "记录交易"
            ) {
                isRecordingTrade = true
            }

            if appModel.recordedTrades.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("还没有本地交易记录")
                            .font(.headline)
                        Text("记录成交后可用于成本复核、现金变化和后续策略复盘。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 16)
            } else {
                ForEach(appModel.recordedTrades.prefix(8)) { trade in
                    HStack(spacing: 12) {
                        StatusPill(
                            text: trade.side.rawValue,
                            tint: trade.side == .buy ? AppTheme.positive : AppTheme.negative,
                            systemImage: trade.side == .buy ? "arrow.down.left" : "arrow.up.right"
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(trade.name)
                                .font(.subheadline.weight(.semibold))
                            Text("\(trade.symbol) · \(AppFormat.dateTime(trade.tradedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(AppFormat.quantity(trade.quantity)) × \(AppFormat.money(trade.price, currency: trade.currency, decimals: 2))")
                                .font(.subheadline.monospacedDigit())
                            Text("折算 \(AppFormat.money(trade.grossAmountInBase, currency: appModel.portfolio.currency))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5)

                    if trade.id != appModel.recordedTrades.prefix(8).last?.id {
                        Divider()
                    }
                }
            }
        }
        .cardStyle()
    }

    private var dailyProfitPercent: Double {
        let previousAssets = appModel.portfolio.totalAssets - appModel.portfolio.dailyProfit
        return previousAssets == 0 ? 0 : appModel.portfolio.dailyProfit / previousAssets * 100
    }

    private var sortedContributors: [Holding] {
        appModel.portfolio.holdings.sorted { $0.estimatedDailyProfit > $1.estimatedDailyProfit }
    }

    private var attentionRules: [StrategyRule] {
        appModel.evaluatedStrategyRules.filter { $0.state != .healthy }
    }
}

private struct HoldingClassificationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let holding: Holding
    let onSave: (String, String) -> Void
    @State private var sector: String
    @State private var note: String

    init(holding: Holding, onSave: @escaping (String, String) -> Void) {
        self.holding = holding
        self.onSave = onSave
        _sector = State(initialValue: holding.sector == "待分类" ? "" : holding.sector)
        _note = State(initialValue: holding.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("设置行业分类")
                    .font(.title2.weight(.semibold))
                Text("\(holding.name) · \(holding.symbol)")
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("行业", text: $sector, prompt: Text("例如：银行、保险、资讯科技"))
                TextField("本地备注", text: $note, axis: .vertical)
                    .lineLimit(3...6)
                LabeledContent("数据边界", value: "仅保存在本机，不写回长桥")
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    onSave(sector, note)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 500, height: 330)
    }
}
