import SwiftUI

private enum LearningScope: String, CaseIterable, Identifiable {
    case today = "今日学习"
    case path = "学习路径"
    case investors = "投资人方法"
    case review = "复习"
    case methodology = "我的方法论"
    case notes = "学习笔记"

    var id: String { rawValue }
}

struct LearningView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var scope: LearningScope = .today
    @State private var selectedAnswers: [String: Int] = [:]
    @State private var submittedQuizUnitID: String?
    @State private var selectedQuestionUnit: LearningUnit?
    @State private var selectedLesson: LearningUnit?
    @State private var selectedInvestorID = LearningCurriculum.investorProfiles.first?.id ?? ""
    @State private var selectedInvestorQuestion: InvestorThinkingProfile?
    @State private var selectedMethodology: MethodologySection = .assetAllocation
    @State private var methodologyDraft = ""
    @State private var noteBody = ""
    @State private var noteUnitID = "none"

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    eyebrow: "LEARNING",
                    title: "投资技能学习",
                    subtitle: "28 天只学必要知识，最终形成可执行的个人投资方法论。"
                ) {
                    HStack {
                        if appModel.learningSettings.workspacePath != nil {
                            Button {
                                appModel.syncLearningWorkspace()
                            } label: {
                                Label("同步 Codex 内容", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }

                        Button {
                            appModel.connectLearningWorkspace()
                        } label: {
                            Label(
                                appModel.learningSettings.workspacePath == nil ? "连接 Codex" : "更换文件夹",
                                systemImage: "folder.badge.gearshape"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Picker("学习页面", selection: $scope) {
                    ForEach(LearningScope.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 940)
            }
            .padding(.horizontal, 26)
            .padding(.top, 26)
            .padding(.bottom, 18)

            Divider()

            Group {
                switch scope {
                case .today: todayView
                case .path: pathView
                case .investors: investorsView
                case .review: reviewView
                case .methodology: methodologyView
                case .notes: notesView
                }
            }
        }
        .background(AppTheme.canvas)
        .sheet(item: $selectedQuestionUnit) { unit in
            CodexQuestionSheet(unit: unit)
                .environmentObject(appModel)
        }
        .sheet(item: $selectedLesson) { unit in
            LearningLessonSheet(unit: unit)
                .environmentObject(appModel)
        }
        .sheet(item: $selectedInvestorQuestion) { profile in
            InvestorQuestionSheet(profile: profile)
                .environmentObject(appModel)
        }
        .onAppear {
            loadMethodologyDraft()
            if appModel.learningSettings.workspacePath != nil {
                appModel.syncLearningWorkspace()
            }
        }
        .onChange(of: selectedMethodology) { loadMethodologyDraft() }
    }

    private var todayView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let message = appModel.learningMessage {
                    learningMessageBanner(message)
                }

                progressHero
                codexConnectionCard

                if let unit = appModel.currentLearningUnit {
                    lessonCard(unit)
                    quizCard(unit)
                } else {
                    completionCard
                }
            }
            .padding(26)
        }
    }

    private var progressHero: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle()
                    .stroke(AppTheme.accent.opacity(0.14), lineWidth: 11)
                Circle()
                    .trim(from: 0, to: max(appModel.learningCompletionPercent, 0.015))
                    .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text("\(appModel.completedLessonCount)")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                    Text("/ 28 天")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 8) {
                Text("第 \(appModel.learningWeek) 周 · \(currentTrackTitle)")
                    .font(.title2.weight(.semibold))
                Text(currentTrackOutcome)
                    .font(.body)
                    .foregroundStyle(.secondary)
                ProgressView(value: appModel.learningCompletionPercent)
                    .frame(maxWidth: 420)
                Text("每日 \(appModel.learningSettings.dailyMinutes) 分钟 · 每天 \(appModel.learningSettings.generationTimeLabel) 生成新内容")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Label("资产配置方法", systemImage: "chart.pie")
                Label("选股评分卡", systemImage: "list.number")
                Label("行业分析模板", systemImage: "building.columns")
                Label("投资手册 v1.0", systemImage: "book.closed")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var codexConnectionCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 24))
                .foregroundStyle(AppTheme.info)
                .frame(width: 48, height: 48)
                .background(AppTheme.info.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Codex 学习上下文")
                        .font(.headline)
                    StatusPill(
                        text: appModel.learningSyncState.label,
                        tint: appModel.learningSettings.workspacePath == nil ? AppTheme.warning : AppTheme.positive
                    )
                }
                Text(workspaceDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle(
                "允许使用持仓代码与行业作为案例",
                isOn: Binding(
                    get: { appModel.learningSettings.holdingsContextEnabled },
                    set: { appModel.setHoldingsLearningContextEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .help("关闭时 Codex 不会收到任何持仓信息；开启后也只包含代码、名称、资产类型和行业。")
        }
        .cardStyle()
    }

    private func lessonCard(_ unit: LearningUnit) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        StatusPill(text: "第 \(unit.day) 天", tint: tint(for: unit.track))
                        StatusPill(
                            text: unit.source.rawValue,
                            tint: unit.source == .codex ? AppTheme.info : .secondary,
                            systemImage: unit.source == .codex ? "sparkles" : "book.closed"
                        )
                    }
                    Text(unit.title)
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                    Text(unit.objective)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(unit.durationLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(unit.summary)
                .font(.body)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("今天只记住三件事")
                        .font(.headline)
                    ForEach(unit.keyPoints, id: \.self) { point in
                        EvidenceRow(text: point)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                VStack(alignment: .leading, spacing: 9) {
                    Label("案例", systemImage: "lightbulb.fill")
                        .font(.headline)
                        .foregroundStyle(AppTheme.warning)
                    Text(unit.example)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Divider()
                    Label("今日练习", systemImage: "pencil.and.list.clipboard")
                        .font(.headline)
                    Text(unit.exercise)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }

            HStack {
                confidencePicker(unit)
                Spacer()
                Button {
                    selectedQuestionUnit = unit
                } label: {
                    Label("基于本课问 Codex", systemImage: "bubble.left.and.bubble.right")
                }
                Button {
                    appModel.toggleLessonCompletion(unit)
                } label: {
                    Label(
                        appModel.progress(for: unit).status == .completed ? "恢复学习" : "完成今日学习",
                        systemImage: appModel.progress(for: unit).status == .completed
                            ? "arrow.uturn.backward"
                            : "checkmark.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .cardStyle()
    }

    private func quizCard(_ unit: LearningUnit) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "快速检查", subtitle: "答错不会影响课程进度，只会进入复习清单")

            ForEach(unit.quiz) { question in
                VStack(alignment: .leading, spacing: 10) {
                    Text(question.prompt)
                        .font(.headline)

                    ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                        Button {
                            selectedAnswers[question.id] = index
                        } label: {
                            HStack {
                                Image(systemName: selectedAnswers[question.id] == index ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(AppTheme.accent)
                                Text(option)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                selectedAnswers[question.id] == index
                                    ? AppTheme.accentSoft
                                    : Color.primary.opacity(0.035),
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if submittedQuizUnitID == unit.id {
                        let isCorrect = selectedAnswers[question.id] == question.correctIndex
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: isCorrect ? "checkmark.circle.fill" : "arrow.counterclockwise.circle.fill")
                                .foregroundStyle(isCorrect ? AppTheme.positive : AppTheme.warning)
                            Text(question.explanation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack {
                if let score = appModel.progress(for: unit).quizScore {
                    StatusPill(
                        text: "最近得分 \(Int(score))",
                        tint: score >= 80 ? AppTheme.positive : AppTheme.warning
                    )
                }
                Spacer()
                Button("提交答案") { submitQuiz(unit) }
                    .buttonStyle(.bordered)
                    .disabled(unit.quiz.contains { selectedAnswers[$0.id] == nil })
            }
        }
        .cardStyle()
    }

    private var pathView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(
                    title: "4 周最小必要课程",
                    subtitle: "每周 5 天核心知识 + 1 天实践 + 1 天方法论沉淀"
                )

                ForEach(1...4, id: \.self) { week in
                    weekCard(week)
                }
            }
            .padding(26)
        }
    }

    private func weekCard(_ week: Int) -> some View {
        let units = appModel.learningUnits.filter { $0.week == week }
        let track = units.first?.track ?? .integration
        let completed = units.filter { appModel.progress(for: $0).status == .completed }.count

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: track.systemImage)
                    .font(.title2)
                    .foregroundStyle(tint(for: track))
                    .frame(width: 44, height: 44)
                    .background(tint(for: track).opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text("第 \(week) 周 · \(track.rawValue)")
                        .font(.title3.weight(.semibold))
                    Text(track.outcome)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(text: "\(completed)/\(units.count)", tint: completed == units.count ? AppTheme.positive : tint(for: track))
            }

            VStack(spacing: 0) {
                ForEach(Array(units.enumerated()), id: \.element.id) { index, unit in
                    Button {
                        selectedLesson = unit
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: statusIcon(for: unit))
                                .foregroundStyle(statusTint(for: unit))
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("第 \(unit.day) 天 · \(unit.title)")
                                    .font(.subheadline.weight(.medium))
                                Text(unit.objective)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if unit.source == .codex {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(AppTheme.info)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < units.count - 1 { Divider() }
                }
            }
        }
        .cardStyle()
    }

    private var reviewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(
                    title: "需要再看一次",
                    subtitle: "测验低于 80 分或自评信心不足的课程会自动进入这里"
                )

                if appModel.reviewLearningUnits.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(AppTheme.positive)
                        Text("当前没有待复习内容")
                            .font(.headline)
                        Text("完成测验并记录理解信心后，系统会自动安排薄弱内容。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 210)
                    .cardStyle()
                } else {
                    ForEach(appModel.reviewLearningUnits) { unit in
                        HStack(spacing: 14) {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .font(.title2)
                                .foregroundStyle(AppTheme.warning)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("第 \(unit.day) 天 · \(unit.title)")
                                    .font(.headline)
                                Text(unit.reviewQuestions.first ?? unit.objective)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let score = appModel.progress(for: unit).quizScore {
                                StatusPill(text: "\(Int(score)) 分", tint: AppTheme.warning)
                            }
                            Button("重新学习") { selectedLesson = unit }
                        }
                        .cardStyle()
                    }
                }
            }
            .padding(26)
        }
    }

    private var investorsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 25))
                        .foregroundStyle(AppTheme.info)
                        .frame(width: 50, height: 50)
                        .background(AppTheme.info.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("学方法，不抄答案")
                            .font(.headline)
                        Text("三位投资人的公开材料会作为 28 天课程中的补充镜头。每个方法都配有适用范围、局限和反向练习，不复制个股、仓位或结论。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(text: "一手材料优先", tint: AppTheme.positive, systemImage: "checkmark.seal")
                }
                .cardStyle()

                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("方法目录")
                            .font(.headline)
                            .padding(.horizontal, 9)
                            .padding(.bottom, 3)

                        ForEach(LearningCurriculum.investorProfiles) { profile in
                            Button {
                                selectedInvestorID = profile.id
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(investorTint(profile).gradient)
                                        .frame(width: 9, height: 9)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(profile.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text(profile.identity)
                                            .font(.caption)
                                            .foregroundStyle(
                                                selectedInvestorID == profile.id
                                                    ? Color.white.opacity(0.76)
                                                    : .secondary
                                            )
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                }
                                .foregroundStyle(selectedInvestorID == profile.id ? .white : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .background(
                                    selectedInvestorID == profile.id ? investorTint(profile) : .clear,
                                    in: RoundedRectangle(cornerRadius: 9)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 250, alignment: .leading)
                    .cardStyle(padding: 10)

                    investorProfileDetail(selectedInvestorProfile)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                SectionTitle(
                    title: "把三种方法合成自己的流程",
                    subtitle: "企业所有者视角 × 反向检查 × 商业模式与本分；冲突时以你的风险边界和证据为准"
                )

                HStack(alignment: .top, spacing: 14) {
                    comparisonCard(
                        title: "选股前",
                        icon: "scope",
                        tint: AppTheme.info,
                        points: ["能力圈：我真的懂什么？", "商业模式：客户为何长期付费？", "不为清单：哪些情况直接放弃？"]
                    )
                    comparisonCard(
                        title: "研究中",
                        icon: "magnifyingglass.circle",
                        tint: AppTheme.accent,
                        points: ["所有者视角：企业怎样增加每股价值？", "激励检查：谁因什么做出选择？", "反向思考：论点最可能怎样失败？"]
                    )
                    comparisonCard(
                        title: "行动前",
                        icon: "checklist.checked",
                        tint: AppTheme.warning,
                        points: ["价格和价值是否留有余地？", "是否能承受长期不交易？", "证伪条件与复核日期是否写清？"]
                    )
                }
            }
            .padding(26)
        }
    }

    private func investorProfileDetail(_ profile: InvestorThinkingProfile) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(profile.name)
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                        StatusPill(text: profile.identity, tint: investorTint(profile))
                    }
                    Text(profile.oneLineMethod)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    selectedInvestorQuestion = profile
                } label: {
                    Label("基于该方法问 Codex", systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("核心原则")
                        .font(.headline)
                    ForEach(profile.principles, id: \.self) { principle in
                        EvidenceRow(text: principle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 9) {
                    Text("可执行流程")
                        .font(.headline)
                    ForEach(Array(profile.decisionProcess.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(investorTint(profile), in: Circle())
                            Text(step)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            VStack(alignment: .leading, spacing: 9) {
                Label("不能直接照搬", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.warning)
                ForEach(profile.limitations, id: \.self) { limitation in
                    EvidenceRow(text: limitation, positive: false)
                }
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("会影响的方法论页面")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack {
                        ForEach(profile.usefulFor) { section in
                            StatusPill(text: section.rawValue, tint: investorTint(profile))
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 7) {
                    Text("公开原始材料")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(profile.sources) { source in
                        if let url = source.linkURL {
                            Link(destination: url) {
                                Label(source.title, systemImage: "arrow.up.right.square")
                                    .font(.caption)
                            }
                            .help(source.note)
                        }
                    }
                }
            }
        }
        .cardStyle()
    }

    private func comparisonCard(
        title: String,
        icon: String,
        tint: Color,
        points: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(tint)
            ForEach(points, id: \.self) { point in
                EvidenceRow(text: point)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var methodologyView: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("个人投资手册 v1.0")
                        .font(.headline)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 5)

                    ForEach(MethodologySection.allCases) { section in
                        Button {
                            selectedMethodology = section
                        } label: {
                            HStack {
                                Image(systemName: section.systemImage)
                                    .frame(width: 20)
                                Text(section.rawValue)
                                Spacer()
                                if selectedMethodology == section {
                                    Image(systemName: "chevron.right")
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(
                                selectedMethodology == section ? AppTheme.accentSoft : .clear,
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 240, alignment: .leading)
                .cardStyle(padding: 10)

                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle(
                        title: selectedMethodology.rawValue,
                        subtitle: "每天只更新一小段；第 28 天完成第一版，不追求一次写完"
                    )

                    TextEditor(text: $methodologyDraft)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 360)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))

                    HStack {
                        Text("内容保存在本机 SQLite；连接后同步为 Markdown，供 Codex 继续辅导。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("恢复模板") { methodologyDraft = selectedMethodology.starter }
                        Button("保存方法论") {
                            appModel.updateMethodology(selectedMethodology, content: methodologyDraft)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
            .padding(26)
        }
    }

    private var notesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "记录一个想法", subtitle: "记录疑问、案例、反方观点或准备加入方法论的规则")

                    Picker("关联课程", selection: $noteUnitID) {
                        Text("不关联课程").tag("none")
                        ForEach(appModel.learningUnits) { unit in
                            Text("第 \(unit.day) 天 · \(unit.title)").tag(unit.id)
                        }
                    }
                    .frame(maxWidth: 440)

                    TextEditor(text: $noteBody)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 110)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))

                    HStack {
                        Spacer()
                        Button("保存笔记") {
                            appModel.addLearningNote(
                                body: noteBody,
                                unitID: noteUnitID == "none" ? nil : noteUnitID
                            )
                            noteBody = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .cardStyle()

                SectionTitle(title: "最近笔记", subtitle: "\(appModel.learningNotes.count) 条保存在本机")

                if appModel.learningNotes.isEmpty {
                    Text("还没有学习笔记。完成今天的练习后，先记录一个仍然不确定的问题。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .cardStyle()
                } else {
                    ForEach(appModel.learningNotes) { note in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                if let unitID = note.unitID,
                                   let unit = appModel.learningUnits.first(where: { $0.id == unitID }) {
                                    StatusPill(text: "第 \(unit.day) 天", tint: tint(for: unit.track))
                                } else {
                                    StatusPill(text: "随手笔记", tint: .secondary)
                                }
                                Text(AppFormat.dateTime(note.updatedAt))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Button(role: .destructive) {
                                    appModel.deleteLearningNote(note)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                            Text(note.body)
                                .font(.body)
                        }
                        .cardStyle()
                    }
                }
            }
            .padding(26)
        }
    }

    private var completionCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 42))
                .foregroundStyle(AppTheme.warning)
            Text("4 周核心课程已完成")
                .font(.title2.weight(.bold))
            Text("现在请进入“我的方法论”，定稿个人投资手册 v1.0，并安排下一次月度复盘。")
                .font(.body)
                .foregroundStyle(.secondary)
            Button("打开我的方法论") { scope = .methodology }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .cardStyle()
    }

    private func confidencePicker(_ unit: LearningUnit) -> some View {
        HStack(spacing: 7) {
            Text("理解信心")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(1...5, id: \.self) { value in
                Button {
                    appModel.setLearningConfidence(value, for: unit)
                } label: {
                    Image(systemName: value <= appModel.progress(for: unit).confidence ? "circle.fill" : "circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(value <= appModel.progress(for: unit).confidence ? AppTheme.accent : .secondary)
                .help("\(value) / 5")
            }
        }
    }

    private func submitQuiz(_ unit: LearningUnit) {
        guard !unit.quiz.isEmpty else { return }
        let correct = unit.quiz.filter { selectedAnswers[$0.id] == $0.correctIndex }.count
        let score = Double(correct) / Double(unit.quiz.count) * 100
        submittedQuizUnitID = unit.id
        appModel.recordQuizScore(score, for: unit)
    }

    private func loadMethodologyDraft() {
        methodologyDraft = appModel.methodologyNotes.first {
            $0.section == selectedMethodology
        }?.content ?? selectedMethodology.starter
    }

    private func learningMessageBanner(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(AppTheme.info)
            Text(message)
                .font(.subheadline)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.info.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }

    private var currentTrackTitle: String {
        appModel.currentLearningUnit?.track.rawValue ?? LearningTrack.integration.rawValue
    }

    private var currentTrackOutcome: String {
        appModel.currentLearningUnit?.track.outcome ?? LearningTrack.integration.outcome
    }

    private var workspaceDescription: String {
        guard let path = appModel.learningSettings.workspacePath else {
            return "连接项目中的 Learning 文件夹后，Codex 每日课程、进度和提问上下文可以互通。"
        }
        return path
    }

    private func statusIcon(for unit: LearningUnit) -> String {
        switch appModel.progress(for: unit).status {
        case .notStarted: "circle"
        case .inProgress: "circle.dotted"
        case .completed: "checkmark.circle.fill"
        }
    }

    private func statusTint(for unit: LearningUnit) -> Color {
        appModel.progress(for: unit).status == .completed ? AppTheme.positive : tint(for: unit.track)
    }

    private func tint(for track: LearningTrack) -> Color {
        switch track {
        case .assetAllocation: AppTheme.info
        case .stockSelection: AppTheme.accent
        case .industryResearch: AppTheme.warning
        case .integration: Color.purple
        }
    }

    private var selectedInvestorProfile: InvestorThinkingProfile {
        LearningCurriculum.investorProfiles.first { $0.id == selectedInvestorID }
            ?? LearningCurriculum.investorProfiles[0]
    }

    private func investorTint(_ profile: InvestorThinkingProfile) -> Color {
        switch profile.accentName {
        case "purple": Color.purple
        case "orange": AppTheme.warning
        default: AppTheme.info
        }
    }
}

private struct CodexQuestionSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    let unit: LearningUnit
    @State private var question = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("基于本课问 Codex")
                        .font(.title2.weight(.bold))
                    Text("第 \(unit.day) 天 · \(unit.title)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
            }

            Text("推荐问题")
                .font(.headline)
            ForEach(unit.suggestedCodexQuestions, id: \.self) { suggestion in
                Button {
                    question = suggestion
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(AppTheme.info)
                        Text(suggestion)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }

            TextEditor(text: $question)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(9)
                .frame(minHeight: 120)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))

            Text("应用会把本课、测验结果和方法论草稿写入 Learning/questions/current-context.md，并复制一条可直接粘贴到 Codex 的提问。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if appModel.learningSettings.workspacePath == nil {
                Label("请先关闭此窗口，并在学习页连接项目的 Learning 文件夹。", systemImage: "folder.badge.questionmark")
                    .font(.caption)
                    .foregroundStyle(AppTheme.warning)
            }

            HStack {
                Spacer()
                Button("准备并复制问题") {
                    if appModel.prepareCodexQuestion(for: unit, question: question) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || appModel.learningSettings.workspacePath == nil
                )
            }
        }
        .padding(22)
        .frame(width: 620, height: 570)
    }
}

private struct InvestorQuestionSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    let profile: InvestorThinkingProfile
    @State private var question = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("基于投资人方法问 Codex")
                        .font(.title2.weight(.bold))
                    Text("\(profile.name) · 学习方法，不模仿结论")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
            }

            Text("推荐问题")
                .font(.headline)
            ForEach(profile.practiceQuestions, id: \.self) { suggestion in
                Button {
                    question = suggestion
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(AppTheme.info)
                        Text(suggestion)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }

            TextEditor(text: $question)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(9)
                .frame(minHeight: 120)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))

            Text("应用会把方法摘要、局限、原始来源和你的个人方法论草稿写入 Learning/questions/current-context.md，再复制可直接粘贴到 Codex 的问题。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if appModel.learningSettings.workspacePath == nil {
                Label("请先关闭此窗口，并在学习页连接项目的 Learning 文件夹。", systemImage: "folder.badge.questionmark")
                    .font(.caption)
                    .foregroundStyle(AppTheme.warning)
            }

            HStack {
                Spacer()
                Button("准备并复制问题") {
                    if appModel.prepareCodexQuestion(for: profile, question: question) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || appModel.learningSettings.workspacePath == nil
                )
            }
        }
        .padding(22)
        .frame(width: 660, height: 620)
    }
}

private struct LearningLessonSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    let unit: LearningUnit

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    StatusPill(text: "第 \(unit.day) 天", tint: AppTheme.accent)
                    StatusPill(text: unit.track.rawValue, tint: AppTheme.info)
                    Spacer()
                    Button("关闭") { dismiss() }
                }

                Text(unit.title)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text(unit.objective)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(unit.summary)
                    .font(.body)

                Divider()
                Text("核心要点")
                    .font(.headline)
                ForEach(unit.keyPoints, id: \.self) { EvidenceRow(text: $0) }

                GroupBox("案例") {
                    Text(unit.example)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                }
                GroupBox("练习") {
                    Text(unit.exercise)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                }

                HStack {
                    Spacer()
                    Button(appModel.progress(for: unit).status == .completed ? "恢复学习" : "标记完成") {
                        appModel.toggleLessonCompletion(unit)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .frame(width: 700, height: 680)
    }
}
