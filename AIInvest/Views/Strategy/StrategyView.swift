import SwiftUI

struct StrategyView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isEditingStrategy = false
    @State private var editingThesis: InvestmentThesis?
    @State private var isConfirmingCodexGeneration = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    eyebrow: "DISCIPLINE",
                    title: "策略",
                    subtitle: "把投资偏好变成可以持续检查的规则。"
                ) {
                    HStack {
                        Button("编辑策略") { isEditingStrategy = true }
                        Button {
                            isConfirmingCodexGeneration = true
                        } label: {
                            if appModel.codexGenerationScope == .strategy {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Codex 生成策略", systemImage: "sparkles")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appModel.codexGenerationScope != nil)
                    }
                }

                if let message = appModel.codexGenerationMessage {
                    CodexGenerationBanner(
                        message: message,
                        isRunning: appModel.codexGenerationScope != nil
                    )
                }

                strategyHero

                if appModel.strategy.generatedBy != nil {
                    codexStrategyContext
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "规则检查", subtitle: "每次持仓同步后由程序确定性计算")
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(appModel.evaluatedStrategyRules) { rule in
                            ruleCard(rule)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(
                        title: "持仓投资论点",
                        subtitle: "\(completedThesisCount)/\(appModel.strategy.theses.count) 个持仓已有可复核论点"
                    )

                    VStack(spacing: 0) {
                        ForEach(Array(appModel.strategy.theses.enumerated()), id: \.offset) { index, thesis in
                            Button {
                                editingThesis = thesis
                            } label: {
                                thesisRow(thesis)
                            }
                            .buttonStyle(.plain)
                            if index < appModel.strategy.theses.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .cardStyle(padding: 0)
                }
            }
            .padding(26)
        }
        .background(AppTheme.canvas)
        .sheet(isPresented: $isEditingStrategy) {
            StrategyEditorSheet(strategy: appModel.strategy) { name, description, riskProfile in
                appModel.updateStrategy(
                    name: name,
                    description: description,
                    riskProfile: riskProfile
                )
            }
        }
        .sheet(item: $editingThesis) { thesis in
            ThesisEditorSheet(thesis: thesis) { updatedThesis in
                appModel.updateThesis(updatedThesis)
            }
        }
        .confirmationDialog(
            "使用 Codex 重新生成策略？",
            isPresented: $isConfirmingCodexGeneration,
            titleVisibility: .visible
        ) {
            Button("开始生成") {
                Task { await appModel.generateStrategyWithCodex() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("Codex 将读取当前持仓权重、现金、现有论点和最近研报，并实时检索公开信息。生成成功后会更新策略名称、阈值和当前持仓论点；不会执行交易。")
        }
    }

    private var strategyHero: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(AppTheme.accent.opacity(0.16), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: Double(appModel.disciplineScore) / 100)
                    .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(appModel.disciplineScore)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("纪律分")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 116, height: 116)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(appModel.strategy.name)
                        .font(.title2.weight(.semibold))
                    StatusPill(text: appModel.strategy.riskProfile, tint: AppTheme.accent)
                }
                Text(appModel.strategy.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("最近更新 \(AppFormat.shortDate(appModel.strategy.updatedAt))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 9) {
                Label("证据优先于结论", systemImage: "checkmark.seal.fill")
                Label("风险控制优先", systemImage: "shield.checkered")
                Label("永不自动下单", systemImage: "hand.raised.fill")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var codexStrategyContext: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(
                title: "Codex 策略依据",
                subtitle: "近期公开信息、金融理论与组合约束的结构化结果"
            )
            VStack(alignment: .leading, spacing: 16) {
                if let summary = appModel.strategy.analysisSummary, !summary.isEmpty {
                    reviewBlock("生成摘要", values: [summary])
                }
                if let context = appModel.strategy.marketContext, !context.isEmpty {
                    Divider()
                    reviewBlock("近期背景", values: context)
                }
                if let theory = appModel.strategy.theoryBasis, !theory.isEmpty {
                    Divider()
                    reviewBlock("理论与策略依据", values: theory)
                }
                if let sources = appModel.strategy.sources, !sources.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
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
                                .font(.subheadline)
                            }
                        }
                    }
                }
            }
            .cardStyle()
        }
    }

    private func reviewBlock(_ title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(values, id: \.self) { value in
                Text("• \(value)")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func ruleCard(_ rule: StrategyRule) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StatusPill(text: rule.state.rawValue, tint: tint(for: rule.state), systemImage: icon(for: rule.state))
                Spacer()
                Text(rule.currentValue)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }

            Text(rule.title)
                .font(.headline)
            Text(rule.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text("策略阈值")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(rule.limitValue)
                    .fontWeight(.medium)
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, minHeight: 125, alignment: .topLeading)
        .cardStyle()
    }

    private func thesisRow(_ thesis: InvestmentThesis) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(thesis.companyName.prefix(1)))
                    .font(.headline)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 9))
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(thesis.companyName)
                        .font(.headline)
                    Text(thesis.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    StatusPill(text: thesis.health.rawValue, tint: tint(for: thesis.health))
                }
                Text(thesis.summary)
                    .font(.subheadline)
                Text(thesis.keyEvidence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("下次复核")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(AppFormat.shortDate(thesis.nextReviewAt))
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding(16)
        .contentShape(Rectangle())
    }

    private var completedThesisCount: Int {
        appModel.strategy.theses.filter { $0.health != .missing }.count
    }

    private func tint(for state: RuleState) -> Color {
        switch state {
        case .healthy: AppTheme.positive
        case .warning: AppTheme.warning
        case .breached: AppTheme.negative
        }
    }

    private func icon(for state: RuleState) -> String {
        switch state {
        case .healthy: "checkmark"
        case .warning: "exclamationmark"
        case .breached: "xmark"
        }
    }

    private func tint(for health: ThesisHealth) -> Color {
        switch health {
        case .supported: AppTheme.positive
        case .review: AppTheme.warning
        case .missing: AppTheme.negative
        }
    }
}

private struct StrategyEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description: String
    @State private var riskProfile: String
    let onSave: (String, String, String) -> Void

    init(
        strategy: InvestmentStrategy,
        onSave: @escaping (String, String, String) -> Void
    ) {
        _name = State(initialValue: strategy.name)
        _description = State(initialValue: strategy.description)
        _riskProfile = State(initialValue: strategy.riskProfile)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("编辑投资策略")
                    .font(.title2.weight(.semibold))
                Text("写清目标与风险边界，持仓同步不会覆盖这些内容。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("策略名称", text: $name)
                TextField("风险画像", text: $riskProfile)
                TextField("策略说明", text: $description, axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    onSave(name, description, riskProfile)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 520, height: 390)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !riskProfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct ThesisEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let thesis: InvestmentThesis
    let onSave: (InvestmentThesis) -> Void

    @State private var summary: String
    @State private var keyEvidence: String
    @State private var nextReviewAt: Date
    @State private var health: ThesisHealth

    init(thesis: InvestmentThesis, onSave: @escaping (InvestmentThesis) -> Void) {
        self.thesis = thesis
        self.onSave = onSave
        _summary = State(initialValue: thesis.summary)
        _keyEvidence = State(initialValue: thesis.keyEvidence)
        _nextReviewAt = State(initialValue: thesis.nextReviewAt)
        _health = State(initialValue: thesis.health)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(thesis.companyName) · \(thesis.symbol)")
                    .font(.title2.weight(.semibold))
                Text("更新论点后，建议和复核应以这里的内容为准。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Form {
                Picker("论点状态", selection: $health) {
                    Text("论点有效").tag(ThesisHealth.supported)
                    Text("需要复核").tag(ThesisHealth.review)
                    Text("待补充").tag(ThesisHealth.missing)
                }
                DatePicker("下次复核", selection: $nextReviewAt, displayedComponents: .date)
                TextField("持有逻辑", text: $summary, axis: .vertical)
                    .lineLimit(3...6)
                TextField("关键证据 / 失效条件", text: $keyEvidence, axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存论点") {
                    onSave(
                        InvestmentThesis(
                            symbol: thesis.symbol,
                            companyName: thesis.companyName,
                            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
                            keyEvidence: keyEvidence.trimmingCharacters(in: .whitespacesAndNewlines),
                            nextReviewAt: nextReviewAt,
                            health: health
                        )
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 580, height: 500)
    }

    private var isValid: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !keyEvidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
