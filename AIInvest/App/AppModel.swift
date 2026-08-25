import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection: AppSection? = .holdings
    @Published private(set) var portfolio: PortfolioSnapshot
    @Published private(set) var strategy: InvestmentStrategy
    @Published private(set) var advice: [AdviceItem]
    @Published private(set) var schedules: [ResearchSchedule]
    @Published private(set) var reports: [IndustryReport]
    @Published private(set) var recordedTrades: [RecordedTrade]
    @Published private(set) var learningUnits: [LearningUnit]
    @Published private(set) var lessonProgress: [String: LessonProgress]
    @Published private(set) var methodologyNotes: [MethodologyNote]
    @Published private(set) var learningNotes: [LearningNote]
    @Published private(set) var learningSettings: LearningSettings
    @Published private(set) var learningSyncState: LearningSyncState
    @Published private(set) var learningMessage: String?
    @Published private(set) var syncState: SyncState
    @Published private(set) var isGeneratingReport = false
    @Published private(set) var databaseStatus: DatabaseStatus
    @Published private(set) var databaseStatistics: DatabaseStatistics?
    @Published private(set) var lastPersistenceError: String?
    @Published private(set) var dataMode: DataMode
    @Published private(set) var longbridgeConnectionState: LongbridgeConnectionState
    @Published private(set) var longbridgeMessage: String?
    @Published private(set) var gptConnectionState: GPTConnectionState
    @Published private(set) var gptModel: String
    @Published private(set) var gptMessage: String?
    @Published private(set) var backgroundReportsEnabled: Bool
    @Published private(set) var monthlyAIBudget: Double
    @Published private(set) var codexGenerationScope: CodexGenerationScope?
    @Published private(set) var codexGenerationMessage: String?

    private let previewLongbridgeService: any LongbridgeProviding
    private let liveLongbridgeService: any LongbridgeConnecting
    private let researchService: any GPTResearchProviding
    private let manualHoldingStore: ManualHoldingStore
    private let database: InvestmentDatabase?
    private let learningWorkspaceService = LearningWorkspaceService()
    private let scheduler = ResearchScheduler()
    private let gptKeychain: any GPTCredentialStoring
    private let codexInvestmentService: any CodexInvestmentGenerating

    init(
        previewLongbridgeService: any LongbridgeProviding = MockLongbridgeService(),
        liveLongbridgeService: any LongbridgeConnecting = LongbridgeCLIService(),
        researchService: any GPTResearchProviding = MockGPTResearchService(),
        gptKeychain: any GPTCredentialStoring = GPTKeychainStore(),
        codexInvestmentService: any CodexInvestmentGenerating = CodexCLIInvestmentService(),
        manualHoldingStore: ManualHoldingStore = ManualHoldingStore(),
        database: InvestmentDatabase? = nil,
        initialPayload: WorkspacePayload = PreviewData.workspace()
    ) {
        self.previewLongbridgeService = previewLongbridgeService
        self.liveLongbridgeService = liveLongbridgeService
        self.researchService = researchService
        self.gptKeychain = gptKeychain
        self.codexInvestmentService = codexInvestmentService
        self.manualHoldingStore = manualHoldingStore

        let syncedHoldings = initialPayload.portfolio.holdings.filter { $0.source == .longbridge }
        let previewManualHoldings = initialPayload.portfolio.holdings.filter { $0.source == .manual }
        let legacyManualHoldings = manualHoldingStore.loadForMigration()
        let fallbackPortfolio = PortfolioSnapshot(
            holdings: syncedHoldings + (legacyManualHoldings ?? previewManualHoldings),
            cash: initialPayload.portfolio.cash,
            currency: initialPayload.portfolio.currency,
            updatedAt: initialPayload.portfolio.updatedAt
        )

        var resolvedDatabase = database
        var resolvedPortfolio = fallbackPortfolio
        var resolvedTrades: [RecordedTrade] = []
        var resolvedStatistics: DatabaseStatistics?
        var resolvedStatus: DatabaseStatus
        var persistenceError: String?
        var resolvedLearning = LearningState(
            units: LearningCurriculum.units,
            progress: [:],
            methodology: LearningCurriculum.defaultMethodology,
            notes: [],
            settings: .default
        )
        var resolvedWorkspace = WorkspaceContent(
            strategy: initialPayload.strategy,
            advice: initialPayload.advice,
            schedules: initialPayload.schedules,
            reports: initialPayload.reports
        )

        do {
            if resolvedDatabase == nil {
                resolvedDatabase = try InvestmentDatabase()
            }
            guard let resolvedDatabase else {
                throw DatabaseError.openFailed("数据库实例为空")
            }

            if let storedPortfolio = try resolvedDatabase.loadPortfolio() {
                resolvedPortfolio = storedPortfolio
            } else {
                try resolvedDatabase.savePortfolio(fallbackPortfolio)
            }
            resolvedTrades = try resolvedDatabase.loadTrades()
            try resolvedDatabase.bootstrapLearning(
                units: LearningCurriculum.units,
                settings: .default,
                methodology: LearningCurriculum.defaultMethodology
            )
            resolvedLearning = try resolvedDatabase.loadLearningState()
            if let storedWorkspace = try resolvedDatabase.loadWorkspaceContent() {
                resolvedWorkspace = storedWorkspace
            } else {
                try resolvedDatabase.saveWorkspaceContent(resolvedWorkspace)
            }
            resolvedStatistics = try resolvedDatabase.statistics()
            resolvedStatus = .ready(resolvedDatabase.fileURL.lastPathComponent)
            manualHoldingStore.markMigrationCompleted()
        } catch {
            resolvedStatus = .failed(error.localizedDescription)
            persistenceError = error.localizedDescription
        }

        self.database = resolvedDatabase
        portfolio = resolvedPortfolio
        recordedTrades = resolvedTrades
        learningUnits = resolvedLearning.units
        lessonProgress = resolvedLearning.progress
        methodologyNotes = resolvedLearning.methodology
        learningNotes = resolvedLearning.notes
        learningSettings = resolvedLearning.settings
        if let path = resolvedLearning.settings.workspacePath {
            learningSyncState = .ready(URL(fileURLWithPath: path).lastPathComponent)
        } else {
            learningSyncState = .notConnected
        }
        learningMessage = nil
        databaseStatistics = resolvedStatistics
        databaseStatus = resolvedStatus
        lastPersistenceError = persistenceError
        strategy = resolvedWorkspace.strategy
        advice = resolvedWorkspace.advice
        schedules = resolvedWorkspace.schedules
        reports = resolvedWorkspace.reports
        syncState = .success(resolvedPortfolio.updatedAt)
        dataMode = DataMode(
            rawValue: UserDefaults.standard.string(forKey: "longbridge.dataMode") ?? ""
        ) ?? .preview
        longbridgeConnectionState = .unknown
        longbridgeMessage = nil
        gptModel = UserDefaults.standard.string(forKey: "gpt.model") ?? "gpt-5.4-mini"
        gptMessage = nil
        codexGenerationScope = nil
        codexGenerationMessage = nil
        backgroundReportsEnabled = UserDefaults.standard.object(forKey: "gpt.backgroundReportsEnabled") as? Bool ?? true
        if UserDefaults.standard.object(forKey: "gpt.monthlyBudget") == nil {
            monthlyAIBudget = 100
        } else {
            monthlyAIBudget = max(UserDefaults.standard.double(forKey: "gpt.monthlyBudget"), 0)
        }
        do {
            gptConnectionState = try gptKeychain.loadAPIKey() == nil
                ? .notConfigured
                : .configured
        } catch {
            gptConnectionState = .failed(error.localizedDescription)
        }
        refreshRuleAdvice()
    }

    var unreadAdviceCount: Int {
        advice.filter { $0.status == .pending }.count
    }

    var unreadReportCount: Int {
        reports.filter(\.isUnread).count
    }

    var manualHoldingCount: Int {
        portfolio.holdings.filter { $0.source == .manual }.count
    }

    var completedLessonCount: Int {
        lessonProgress.values.filter { $0.status == .completed }.count
    }

    var learningCompletionPercent: Double {
        learningUnits.isEmpty ? 0 : Double(completedLessonCount) / Double(learningUnits.count)
    }

    var currentLearningUnit: LearningUnit? {
        learningUnits.first {
            lessonProgress[$0.id]?.status != .completed
        } ?? learningUnits.last
    }

    var reviewLearningUnits: [LearningUnit] {
        learningUnits.filter { unit in
            guard let progress = lessonProgress[unit.id] else { return false }
            let needsQuizReview = (progress.quizScore ?? 100) < 80
            let needsConfidenceReview = progress.confidence > 0 && progress.confidence < 3
            return needsQuizReview || needsConfidenceReview
        }
    }

    var learningWeek: Int {
        currentLearningUnit?.week ?? 4
    }

    func progress(for unit: LearningUnit) -> LessonProgress {
        lessonProgress[unit.id] ?? .empty(for: unit.id)
    }

    var sectorAllocations: [SectorAllocation] {
        let investableHoldings = portfolio.holdings.filter { $0.assetType != .cash }
        let grouped = Dictionary(grouping: investableHoldings, by: \.sector)
        return grouped
            .map { sector, holdings in
                SectorAllocation(sector: sector, marketValue: holdings.reduce(0) { $0 + $1.marketValue })
            }
            .sorted { $0.marketValue > $1.marketValue }
    }

    var largestHolding: Holding? {
        portfolio.holdings
            .filter { $0.assetType != .cash }
            .max { $0.marketValue < $1.marketValue }
    }

    var evaluatedStrategyRules: [StrategyRule] {
        let parameters = strategy.parameters ?? .steadyDefault
        return strategy.rules.map { rule in
            switch rule.id {
            case "single-position":
                let percent = largestHolding.map { portfolioWeight(for: $0) * 100 } ?? 0
                return evaluatedRule(
                    rule,
                    currentValue: percentageLabel(percent),
                    state: upperBoundState(
                        value: percent,
                        warning: parameters.singlePositionWarningPercent,
                        limit: parameters.singlePositionLimitPercent
                    )
                )
            case "sector-position":
                let largestSectorValue = sectorAllocations.first?.marketValue ?? 0
                let percent = portfolio.totalAssets == 0
                    ? 0
                    : largestSectorValue / portfolio.totalAssets * 100
                return evaluatedRule(
                    rule,
                    currentValue: percentageLabel(percent),
                    state: upperBoundState(
                        value: percent,
                        warning: parameters.sectorWarningPercent,
                        limit: parameters.sectorLimitPercent
                    )
                )
            case "cash-buffer":
                let percent = portfolio.cashWeight * 100
                let state: RuleState = percent < parameters.cashMinimumPercent
                    ? .breached
                    : (percent < parameters.cashWarningPercent ? .warning : .healthy)
                return evaluatedRule(
                    rule,
                    currentValue: percentageLabel(percent),
                    state: state
                )
            default:
                return rule
            }
        }
    }

    var disciplineScore: Int {
        let rulePenalty = evaluatedStrategyRules.reduce(0) { result, rule in
            result + (rule.state == .breached ? 20 : (rule.state == .warning ? 8 : 0))
        }
        let thesisPenalty = strategy.theses.filter { $0.health == .missing }.count * 4
        return max(0, 100 - rulePenalty - thesisPenalty)
    }

    func portfolioWeight(for holding: Holding) -> Double {
        portfolio.totalAssets == 0 ? 0 : holding.marketValue / portfolio.totalAssets
    }

    private func evaluatedRule(
        _ rule: StrategyRule,
        currentValue: String,
        state: RuleState
    ) -> StrategyRule {
        StrategyRule(
            id: rule.id,
            title: rule.title,
            description: rule.description,
            currentValue: currentValue,
            limitValue: rule.limitValue,
            state: state
        )
    }

    private func upperBoundState(value: Double, warning: Double, limit: Double) -> RuleState {
        if value > limit { return .breached }
        if value >= warning { return .warning }
        return .healthy
    }

    private func percentageLabel(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1))))%"
    }

    func refresh() async {
        guard syncState != .syncing else { return }
        syncState = .syncing

        do {
            let incomingPortfolio: PortfolioSnapshot
            switch dataMode {
            case .preview:
                incomingPortfolio = try await previewLongbridgeService.loadPortfolio()
            case .live:
                incomingPortfolio = try await liveLongbridgeService.loadPortfolio()
            }

            let manualHoldings = portfolio.holdings.filter { $0.source == .manual }
            let syncedHoldings = enrichSyncedHoldings(
                incomingPortfolio.holdings.filter { $0.source == .longbridge }
            )
            portfolio = PortfolioSnapshot(
                holdings: syncedHoldings + manualHoldings,
                cash: incomingPortfolio.cash,
                currency: incomingPortfolio.currency,
                updatedAt: incomingPortfolio.updatedAt
            )
            persistPortfolio()
            syncState = .success(incomingPortfolio.updatedAt)
            longbridgeMessage = dataMode == .live ? "长桥持仓与行情已同步。" : nil
        } catch {
            syncState = .failed(error.localizedDescription)
            if dataMode == .live {
                longbridgeMessage = "同步失败，当前继续显示上一次保存的数据：\(error.localizedDescription)"
                if error is LongbridgeServiceError {
                    await checkLongbridgeConnection()
                }
            }
        }
    }

    func checkLongbridgeConnection() async {
        guard longbridgeConnectionState != .checking else { return }
        longbridgeConnectionState = .checking
        longbridgeMessage = nil
        longbridgeConnectionState = await liveLongbridgeService.connectionStatus()
    }

    func authenticateLongbridge() async {
        guard let path = longbridgeConnectionState.executablePath else {
            await checkLongbridgeConnection()
            return
        }
        longbridgeConnectionState = .authenticating(path)
        longbridgeMessage = "浏览器授权完成后，这里会自动更新。"

        do {
            try await liveLongbridgeService.authenticate()
            longbridgeConnectionState = await liveLongbridgeService.connectionStatus()
            guard longbridgeConnectionState.isConnected else {
                longbridgeMessage = "授权已结束，但连接检查没有通过，请重试。"
                return
            }
            await useLiveData()
        } catch {
            longbridgeConnectionState = .failed(error.localizedDescription)
            longbridgeMessage = error.localizedDescription
        }
    }

    func useLiveData() async {
        if !longbridgeConnectionState.isConnected {
            await checkLongbridgeConnection()
        }
        guard longbridgeConnectionState.isConnected else {
            longbridgeMessage = "请先完成长桥登录和连接测试。"
            return
        }
        dataMode = .live
        UserDefaults.standard.set(dataMode.rawValue, forKey: "longbridge.dataMode")
        await refresh()
    }

    func usePreviewData() async {
        dataMode = .preview
        UserDefaults.standard.set(dataMode.rawValue, forKey: "longbridge.dataMode")
        longbridgeMessage = "已切换为模拟数据，手动录入持仓不受影响。"
        await refresh()
    }

    func saveGPTConfiguration(apiKey: String, model: String) async {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModel.isEmpty else {
            gptConnectionState = .failed("请填写 OpenAI 模型名称。")
            return
        }

        do {
            let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedKey.isEmpty {
                guard try gptKeychain.loadAPIKey() != nil else {
                    throw OpenAIResearchError.invalidAPIKey
                }
            } else {
                try gptKeychain.save(apiKey: normalizedKey)
            }
            gptModel = normalizedModel
            UserDefaults.standard.set(normalizedModel, forKey: "gpt.model")
            gptConnectionState = .configured
            gptMessage = "API Key 已安全保存，正在测试连接。"
            await validateGPTConnection()
        } catch {
            gptConnectionState = .failed(error.localizedDescription)
            gptMessage = error.localizedDescription
        }
    }

    func validateGPTConnection() async {
        guard gptConnectionState != .validating else { return }
        do {
            guard let apiKey = try gptKeychain.loadAPIKey() else {
                gptConnectionState = .notConfigured
                gptMessage = "请先保存 OpenAI API Key。"
                return
            }
            gptConnectionState = .validating
            gptMessage = nil
            try await OpenAIResearchService(apiKey: apiKey, model: gptModel).validateConnection()
            gptConnectionState = .ready
            gptMessage = "Responses API 连接正常，定时研报将使用 \(gptModel)。"
        } catch {
            gptConnectionState = .failed(error.localizedDescription)
            gptMessage = error.localizedDescription
        }
    }

    func removeGPTConfiguration() {
        do {
            try gptKeychain.delete()
            gptConnectionState = .notConfigured
            gptMessage = "已从 macOS Keychain 移除 API Key；研报任务将使用本地模拟。"
        } catch {
            gptConnectionState = .failed(error.localizedDescription)
            gptMessage = error.localizedDescription
        }
    }

    func updateGPTPreferences(backgroundReportsEnabled: Bool, monthlyBudget: Double) {
        self.backgroundReportsEnabled = backgroundReportsEnabled
        monthlyAIBudget = max(monthlyBudget, 0)
        UserDefaults.standard.set(backgroundReportsEnabled, forKey: "gpt.backgroundReportsEnabled")
        UserDefaults.standard.set(monthlyAIBudget, forKey: "gpt.monthlyBudget")
    }

    func updateAdvice(_ item: AdviceItem, status: AdviceStatus) {
        guard let index = advice.firstIndex(where: { $0.id == item.id }) else { return }
        advice[index].status = status
        persistWorkspaceContent()
    }

    func updateStrategy(name: String, description: String, riskProfile: String) {
        strategy = InvestmentStrategy(
            id: strategy.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            riskProfile: riskProfile.trimmingCharacters(in: .whitespacesAndNewlines),
            updatedAt: .now,
            rules: strategy.rules,
            theses: strategy.theses,
            parameters: strategy.parameters,
            analysisSummary: strategy.analysisSummary,
            theoryBasis: strategy.theoryBasis,
            marketContext: strategy.marketContext,
            sources: strategy.sources,
            generatedBy: strategy.generatedBy
        )
        refreshRuleAdvice()
        persistWorkspaceContent()
    }

    func updateThesis(_ thesis: InvestmentThesis) {
        var theses = strategy.theses
        guard let index = theses.firstIndex(where: { $0.id == thesis.id }) else { return }
        theses[index] = thesis
        strategy = InvestmentStrategy(
            id: strategy.id,
            name: strategy.name,
            description: strategy.description,
            riskProfile: strategy.riskProfile,
            updatedAt: .now,
            rules: strategy.rules,
            theses: theses,
            parameters: strategy.parameters,
            analysisSummary: strategy.analysisSummary,
            theoryBasis: strategy.theoryBasis,
            marketContext: strategy.marketContext,
            sources: strategy.sources,
            generatedBy: strategy.generatedBy
        )
        persistWorkspaceContent()
    }

    func generateStrategyWithCodex() async {
        guard codexGenerationScope == nil else { return }
        codexGenerationScope = .strategy
        codexGenerationMessage = "Codex 正在检索近期公开信息并生成策略，通常需要 1–3 分钟。"
        defer { codexGenerationScope = nil }

        do {
            let draft = try await codexInvestmentService.generateStrategy(context: codexInvestmentContext())
            strategy = makeCodexStrategy(from: draft)
            refreshRuleAdvice()
            codexGenerationMessage = "策略已由 Codex 更新：\(limited(draft.summary, length: 180))"
        } catch is CancellationError {
            codexGenerationMessage = "已取消本次 Codex 策略生成。"
        } catch {
            codexGenerationMessage = error.localizedDescription
        }
    }

    func generateAdviceWithCodex() async {
        guard codexGenerationScope == nil else { return }
        codexGenerationScope = .advice
        codexGenerationMessage = "Codex 正在结合组合、研报、金融理论与近期信息生成建议，通常需要 1–3 分钟。"
        defer { codexGenerationScope = nil }

        do {
            let draft = try await codexInvestmentService.generateAdvice(context: codexInvestmentContext())
            applyCodexAdvice(draft)
            persistWorkspaceContent()
            codexGenerationMessage = "已生成 \(draft.advice.count) 条 Codex 建议：\(limited(draft.summary, length: 180))"
        } catch is CancellationError {
            codexGenerationMessage = "已取消本次 Codex 建议生成。"
        } catch {
            codexGenerationMessage = error.localizedDescription
        }
    }

    func saveManualHolding(_ holding: Holding) {
        guard holding.source == .manual else { return }
        var holdings = portfolio.holdings
        if let index = holdings.firstIndex(where: { $0.id == holding.id }) {
            holdings[index] = holding
        } else {
            holdings.append(holding)
        }
        replacePortfolioHoldings(with: holdings)
    }

    func deleteManualHolding(_ holding: Holding) {
        guard holding.source == .manual else { return }
        replacePortfolioHoldings(with: portfolio.holdings.filter { $0.id != holding.id })
    }

    func updateSyncedHoldingMetadata(_ holding: Holding, sector: String, note: String) {
        guard holding.source == .longbridge,
              let index = portfolio.holdings.firstIndex(where: { $0.id == holding.id }) else { return }
        var holdings = portfolio.holdings
        let normalizedSector = sector.trimmingCharacters(in: .whitespacesAndNewlines)
        holdings[index].sector = normalizedSector.isEmpty ? "待分类" : normalizedSector
        holdings[index].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        holdings[index].updatedAt = .now
        replacePortfolioHoldings(with: holdings)
    }

    @discardableResult
    func recordTrade(
        _ trade: RecordedTrade,
        applyToPosition: Bool,
        applyToCash: Bool
    ) -> Bool {
        guard let database else {
            lastPersistenceError = "SQLite 数据库不可用，交易记录没有保存。"
            return false
        }

        var holdings = portfolio.holdings
        var cash = portfolio.cash
        var didChangePortfolio = false

        if applyToPosition {
            guard let index = holdings.firstIndex(where: { $0.id == trade.holdingID }),
                  holdings[index].source == .manual else {
                lastPersistenceError = "只有手动持仓可以由本地交易记录更新；长桥持仓仍以券商同步为准。"
                return false
            }

            var holding = holdings[index]
            switch trade.side {
            case .buy:
                let newQuantity = holding.shares + trade.quantity
                let oldCost = holding.shares * holding.averageCost
                holding.averageCost = (oldCost + trade.grossAmount + trade.fees) / newQuantity
                holding.shares = newQuantity
                holding.availableShares = newQuantity
                holding.lastPrice = trade.price
                holding.exchangeRateToBase = trade.exchangeRateToBase
                holding.updatedAt = .now
                holdings[index] = holding
            case .sell:
                guard trade.quantity <= holding.shares else {
                    lastPersistenceError = "卖出数量不能超过当前手动持仓数量。"
                    return false
                }
                let remainingQuantity = holding.shares - trade.quantity
                if remainingQuantity <= 0.000_000_01 {
                    holdings.remove(at: index)
                } else {
                    holding.shares = remainingQuantity
                    holding.availableShares = remainingQuantity
                    holding.lastPrice = trade.price
                    holding.exchangeRateToBase = trade.exchangeRateToBase
                    holding.updatedAt = .now
                    holdings[index] = holding
                }
            }
            didChangePortfolio = true
        }

        if applyToCash {
            cash += trade.cashImpactInBase
            didChangePortfolio = true
        }

        let updatedPortfolio = PortfolioSnapshot(
            holdings: holdings,
            cash: cash,
            currency: portfolio.currency,
            updatedAt: .now
        )

        do {
            try database.recordTrade(
                trade,
                updatedPortfolio: didChangePortfolio ? updatedPortfolio : nil
            )
            if didChangePortfolio { portfolio = updatedPortfolio }
            recordedTrades.insert(trade, at: 0)
            if didChangePortfolio { refreshRuleAdvice() }
            refreshDatabaseStatistics()
            databaseStatus = .ready(database.fileURL.lastPathComponent)
            lastPersistenceError = nil
            return true
        } catch {
            databaseStatus = .failed(error.localizedDescription)
            lastPersistenceError = error.localizedDescription
            return false
        }
    }

    func toggleLessonCompletion(_ unit: LearningUnit) {
        var progress = progress(for: unit)
        if progress.status == .completed {
            progress.status = .inProgress
            progress.completedAt = nil
        } else {
            progress.status = .completed
            progress.completedAt = .now
            if progress.confidence == 0 { progress.confidence = 3 }
        }
        progress.updatedAt = .now
        saveLearningProgress(progress)
    }

    func setLearningConfidence(_ confidence: Int, for unit: LearningUnit) {
        var progress = progress(for: unit)
        progress.confidence = min(max(confidence, 1), 5)
        if progress.status == .notStarted { progress.status = .inProgress }
        progress.updatedAt = .now
        saveLearningProgress(progress)
    }

    func recordQuizScore(_ score: Double, for unit: LearningUnit) {
        guard let database else {
            learningMessage = "SQLite 数据库不可用，测验结果没有保存。"
            return
        }
        var progress = progress(for: unit)
        progress.quizScore = min(max(score, 0), 100)
        if progress.status == .notStarted { progress.status = .inProgress }
        progress.confidence = score >= 80 ? max(progress.confidence, 3) : max(progress.confidence, 2)
        progress.updatedAt = .now
        let attempt = QuizAttempt(
            id: UUID().uuidString,
            unitID: unit.id,
            score: progress.quizScore ?? 0,
            attemptedAt: .now
        )
        do {
            try database.recordQuizAttempt(attempt, progress: progress)
            lessonProgress[unit.id] = progress
            learningMessage = score >= 80 ? "测验已通过，结果已保存。" : "已加入复习清单，之后会再次出现。"
            persistLearningContextIfConnected()
            refreshDatabaseStatistics()
        } catch {
            learningMessage = error.localizedDescription
        }
    }

    func updateMethodology(_ section: MethodologySection, content: String) {
        guard let database else {
            learningMessage = "SQLite 数据库不可用，方法论草稿没有保存。"
            return
        }
        let note = MethodologyNote(section: section, content: content, updatedAt: .now)
        do {
            try database.saveMethodologyNote(note)
            if let index = methodologyNotes.firstIndex(where: { $0.section == section }) {
                methodologyNotes[index] = note
            } else {
                methodologyNotes.append(note)
            }
            learningMessage = "“\(section.rawValue)”已保存。"
            persistLearningContextIfConnected()
        } catch {
            learningMessage = error.localizedDescription
        }
    }

    func addLearningNote(body: String, unitID: String?) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let database else { return }
        let note = LearningNote(
            id: UUID().uuidString,
            unitID: unitID,
            body: trimmed,
            createdAt: .now,
            updatedAt: .now
        )
        do {
            try database.saveLearningNote(note)
            learningNotes.insert(note, at: 0)
            learningMessage = "学习笔记已保存到本机。"
            refreshDatabaseStatistics()
        } catch {
            learningMessage = error.localizedDescription
        }
    }

    func deleteLearningNote(_ note: LearningNote) {
        guard let database else { return }
        do {
            try database.deleteLearningNote(id: note.id)
            learningNotes.removeAll { $0.id == note.id }
            refreshDatabaseStatistics()
        } catch {
            learningMessage = error.localizedDescription
        }
    }

    func connectLearningWorkspace() {
        guard let url = learningWorkspaceService.chooseFolder() else { return }
        do {
            try learningWorkspaceService.configure(url: url)
            learningSettings.workspacePath = url.path
            learningSettings.updatedAt = .now
            try database?.saveLearningSettings(learningSettings)
            learningSyncState = .ready(url.lastPathComponent)
            try learningWorkspaceService.exportState(
                progress: lessonProgress,
                methodology: methodologyNotes,
                holdings: portfolio.holdings,
                includeHoldings: learningSettings.holdingsContextEnabled
            )
            syncLearningWorkspace()
        } catch {
            learningSyncState = .failed(error.localizedDescription)
            learningMessage = error.localizedDescription
        }
    }

    func syncLearningWorkspace() {
        guard let database else {
            learningMessage = "SQLite 数据库不可用，无法导入 Codex 课程。"
            return
        }
        learningSyncState = .syncing
        do {
            let result = try learningWorkspaceService.importLessons()
            for unit in result.units { try database.saveLearningUnit(unit) }
            try database.recordLearningSync(
                source: learningSettings.workspacePath ?? "Learning",
                importedCount: result.units.count,
                message: result.ignoredFiles.isEmpty
                    ? "导入成功"
                    : "忽略无法解析的文件：\(result.ignoredFiles.joined(separator: ", "))"
            )
            try reloadLearningState()
            learningSyncState = .succeeded(result.units.count, .now)
            learningMessage = result.ignoredFiles.isEmpty
                ? "已同步 \(result.units.count) 节 Codex 课程。"
                : "已同步 \(result.units.count) 节；\(result.ignoredFiles.count) 个文件格式不符合要求。"
        } catch {
            learningSyncState = .failed(error.localizedDescription)
            learningMessage = error.localizedDescription
        }
    }

    func setHoldingsLearningContextEnabled(_ isEnabled: Bool) {
        learningSettings.holdingsContextEnabled = isEnabled
        learningSettings.updatedAt = .now
        do {
            try database?.saveLearningSettings(learningSettings)
            persistLearningContextIfConnected()
        } catch {
            learningMessage = error.localizedDescription
        }
    }

    @discardableResult
    func prepareCodexQuestion(for unit: LearningUnit, question: String) -> Bool {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            learningMessage = "请先输入想问 Codex 的问题。"
            return false
        }
        do {
            _ = try learningWorkspaceService.prepareQuestionContext(
                unit: unit,
                question: trimmed,
                progress: lessonProgress[unit.id],
                methodology: methodologyNotes
            )
            learningMessage = "提问上下文已写入 Learning 文件夹，问题已复制；现在可直接粘贴到 Codex。"
            return true
        } catch {
            learningMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func prepareCodexQuestion(for profile: InvestorThinkingProfile, question: String) -> Bool {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            learningMessage = "请先输入想问 Codex 的问题。"
            return false
        }
        do {
            _ = try learningWorkspaceService.prepareQuestionContext(
                investor: profile,
                question: trimmed,
                methodology: methodologyNotes
            )
            learningMessage = "\(profile.name)的方法上下文已写入 Learning 文件夹，问题已复制；现在可直接粘贴到 Codex。"
            return true
        } catch {
            learningMessage = error.localizedDescription
            return false
        }
    }

    func markReportRead(_ report: IndustryReport) {
        guard let index = reports.firstIndex(where: { $0.id == report.id }) else { return }
        reports[index].isUnread = false
        persistWorkspaceContent()
    }

    func addSchedule(
        name: String,
        industryScope: String,
        template: ReportTemplate,
        institutionSources: [InstitutionResearchSource] = InstitutionResearchSource.allCases
    ) {
        let nextRun = Calendar.current.date(
            byAdding: template == .monthly ? .month : .day,
            value: template == .weekly ? 7 : 1,
            to: .now
        ) ?? .now

        schedules.insert(
            ResearchSchedule(
                id: UUID().uuidString,
                name: name,
                industryScope: industryScope,
                template: template,
                nextRunAt: nextRun,
                lastRunAt: nil,
                isEnabled: true,
                state: .ready,
                modelName: gptConnectionState.isConfigured ? gptModel : "本地模拟",
                monthlyBudget: monthlyAIBudget,
                institutionSources: institutionSources
            ),
            at: 0
        )
        persistWorkspaceContent()
    }

    func toggleSchedule(_ schedule: ResearchSchedule) {
        guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        schedules[index].isEnabled.toggle()
        schedules[index].state = .ready
        persistWorkspaceContent()
    }

    func deleteSchedule(_ schedule: ResearchSchedule) {
        schedules.removeAll { $0.id == schedule.id }
        persistWorkspaceContent()
    }

    func runSchedule(_ schedule: ResearchSchedule) async {
        guard !isGeneratingReport,
              let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }

        let scheduleID = schedule.id
        let activeSchedule = schedules[index]
        isGeneratingReport = true
        schedules[index].state = .running
        persistWorkspaceContent()
        defer { isGeneratingReport = false }

        do {
            let previous = reports.first { $0.industry == activeSchedule.industryScope }
            var evidence: [ResearchEvidence] = []
            if dataMode == .live {
                do {
                    evidence = try await liveLongbridgeService.loadResearchEvidence(
                        industry: activeSchedule.industryScope,
                        holdings: portfolio.holdings
                    )
                } catch {
                    gptMessage = "长桥新闻证据获取失败，本次将按“证据不足”生成：\(error.localizedDescription)"
                }
            }
            let apiKey = try gptKeychain.loadAPIKey()
            let provider: any GPTResearchProviding = if let apiKey {
                OpenAIResearchService(apiKey: apiKey, model: gptModel)
            } else {
                researchService
            }
            var executionSchedule = activeSchedule
            executionSchedule.modelName = apiKey == nil ? "本地模拟" : gptModel
            let report = try await provider.generateIndustryReport(
                schedule: executionSchedule,
                portfolio: portfolio,
                previousReport: previous,
                evidence: evidence
            )
            reports.insert(report, at: 0)
            if let currentIndex = schedules.firstIndex(where: { $0.id == scheduleID }) {
                schedules[currentIndex].lastRunAt = .now
                schedules[currentIndex].nextRunAt = await scheduler.nextRun(
                    after: .now,
                    template: activeSchedule.template
                )
                schedules[currentIndex].state = .succeeded
                schedules[currentIndex].modelName = report.modelName
            }
            gptMessage = apiKey == nil
                ? "未配置 API Key，本次已生成本地模拟研报。"
                : "已使用 \(gptModel) 生成研报。"
            persistWorkspaceContent()
        } catch {
            if let currentIndex = schedules.firstIndex(where: { $0.id == scheduleID }) {
                schedules[currentIndex].state = .failed
                if schedules[currentIndex].nextRunAt <= .now {
                    schedules[currentIndex].nextRunAt = Calendar.current.date(
                        byAdding: .hour,
                        value: 1,
                        to: .now
                    ) ?? .now
                }
            }
            gptMessage = "研报生成失败：\(error.localizedDescription)"
            persistWorkspaceContent()
        }
    }

    func runDueResearchSchedules(at date: Date = .now) async {
        guard backgroundReportsEnabled else { return }
        let dueSchedules = await scheduler.dueSchedules(in: schedules, at: date)
        for schedule in dueSchedules {
            guard !Task.isCancelled else { return }
            guard let current = schedules.first(where: { $0.id == schedule.id }),
                  current.isEnabled,
                  current.nextRunAt <= date else { continue }
            await runSchedule(current)
        }
    }

    private func saveLearningProgress(_ progress: LessonProgress) {
        guard let database else {
            learningMessage = "SQLite 数据库不可用，学习进度没有保存。"
            return
        }
        do {
            try database.saveLessonProgress(progress)
            lessonProgress[progress.unitID] = progress
            learningMessage = progress.status == .completed ? "今日学习已完成。" : "已恢复为学习中。"
            persistLearningContextIfConnected()
            refreshDatabaseStatistics()
        } catch {
            learningMessage = error.localizedDescription
        }
    }

    private func reloadLearningState() throws {
        guard let database else { return }
        let state = try database.loadLearningState()
        learningUnits = state.units
        lessonProgress = state.progress
        methodologyNotes = state.methodology
        learningNotes = state.notes
        learningSettings = state.settings
        refreshDatabaseStatistics()
    }

    private func persistLearningContextIfConnected() {
        guard learningSettings.workspacePath != nil else { return }
        do {
            try learningWorkspaceService.exportState(
                progress: lessonProgress,
                methodology: methodologyNotes,
                holdings: portfolio.holdings,
                includeHoldings: learningSettings.holdingsContextEnabled
            )
        } catch {
            learningMessage = "本机进度已保存，但 Learning 文件夹同步失败：\(error.localizedDescription)"
        }
    }

    private func replacePortfolioHoldings(with holdings: [Holding]) {
        portfolio = PortfolioSnapshot(
            holdings: holdings,
            cash: portfolio.cash,
            currency: portfolio.currency,
            updatedAt: .now
        )
        persistPortfolio()
    }

    private func enrichSyncedHoldings(_ incoming: [Holding]) -> [Holding] {
        let previous = portfolio.holdings
            .filter { $0.source == .longbridge }
            .reduce(into: [String: Holding]()) { result, holding in
                result[holding.symbol.uppercased()] = holding
            }

        return incoming.map { item in
            guard let existing = previous[item.symbol.uppercased()] else { return item }
            var enriched = item
            if item.sector == "待分类", existing.sector != "待分类" {
                enriched.sector = existing.sector
            }
            if item.assetType == .stock, existing.assetType != .stock {
                enriched.assetType = existing.assetType
            }
            if enriched.note.isEmpty {
                enriched.note = existing.note
            }
            return enriched
        }
    }

    private func codexInvestmentContext() -> CodexInvestmentContext {
        CodexInvestmentContext(
            portfolio: portfolio,
            strategy: strategy,
            evaluatedRules: evaluatedStrategyRules,
            recentReports: reports.sorted { $0.generatedAt > $1.generatedAt },
            dataMode: dataMode
        )
    }

    private func makeCodexStrategy(from draft: CodexStrategyDraft) -> InvestmentStrategy {
        let singleLimit = clamped(draft.singlePositionLimitPercent, minimum: 10, maximum: 50)
        let singleWarning = min(
            clamped(draft.singlePositionWarningPercent, minimum: 5, maximum: 40),
            singleLimit
        )
        let sectorLimit = clamped(draft.sectorLimitPercent, minimum: 15, maximum: 70)
        let sectorWarning = min(
            clamped(draft.sectorWarningPercent, minimum: 10, maximum: 60),
            sectorLimit
        )
        let cashMinimum = clamped(draft.cashMinimumPercent, minimum: 0, maximum: 40)
        let cashWarning = max(
            cashMinimum,
            clamped(draft.cashWarningPercent, minimum: 0, maximum: 50)
        )
        let parameters = StrategyParameters(
            singlePositionWarningPercent: singleWarning,
            singlePositionLimitPercent: singleLimit,
            sectorWarningPercent: sectorWarning,
            sectorLimitPercent: sectorLimit,
            cashMinimumPercent: cashMinimum,
            cashWarningPercent: cashWarning
        )

        let rules = [
            StrategyRule(
                id: "single-position",
                title: "单一持仓上限",
                description: "以分散化、风险容量和持仓论点强度约束个别证券风险",
                currentValue: "待计算",
                limitValue: "≤ \(percentageLimit(singleLimit))",
                state: .healthy
            ),
            StrategyRule(
                id: "sector-position",
                title: "单一行业上限",
                description: "限制相同经济驱动因素造成的行业集中风险",
                currentValue: "待计算",
                limitValue: "≤ \(percentageLimit(sectorLimit))",
                state: .healthy
            ),
            StrategyRule(
                id: "cash-buffer",
                title: "现金缓冲",
                description: "为生活流动性、市场波动和后续研究机会保留缓冲",
                currentValue: "待计算",
                limitValue: "≥ \(percentageLimit(cashMinimum))",
                state: .healthy
            ),
            StrategyRule(
                id: "leverage",
                title: "杠杆与复杂产品",
                description: "稳健策略不使用杠杆、卖空和无法清晰解释损失边界的复杂产品",
                currentValue: "本地账本未记录",
                limitValue: "禁止",
                state: .healthy
            )
        ]

        let draftBySymbol = Dictionary(
            draft.theses.map { ($0.symbol.uppercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let existingBySymbol = Dictionary(
            strategy.theses.map { ($0.symbol.uppercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let theses = portfolio.holdings
            .filter { $0.assetType != .cash }
            .sorted { $0.marketValue > $1.marketValue }
            .map { holding -> InvestmentThesis in
                let symbol = holding.symbol.uppercased()
                guard let generated = draftBySymbol[symbol] else {
                    if let existing = existingBySymbol[symbol] { return existing }
                    return InvestmentThesis(
                        symbol: holding.symbol,
                        companyName: holding.name,
                        summary: "Codex 未返回完整论点，需要手动补充持有逻辑。",
                        keyEvidence: "关键证据与失效条件待核验。",
                        nextReviewAt: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now,
                        health: .missing
                    )
                }
                let reviewDays = min(max(generated.nextReviewDays, 7), 120)
                return InvestmentThesis(
                    symbol: holding.symbol,
                    companyName: holding.name,
                    summary: limited(generated.summary, length: 500),
                    keyEvidence: "关键证据：\(limited(generated.keyEvidence, length: 450))\n失效条件：\(limited(generated.invalidatingConditions, length: 450))",
                    nextReviewAt: Calendar.current.date(byAdding: .day, value: reviewDays, to: .now) ?? .now,
                    health: thesisHealth(generated.health)
                )
            }

        return InvestmentStrategy(
            id: strategy.id,
            name: nonEmpty(draft.strategyName, fallback: "稳健投资策略"),
            description: nonEmpty(draft.strategyDescription, fallback: draft.summary),
            riskProfile: nonEmpty(draft.riskProfile, fallback: "稳健 · 中低频"),
            updatedAt: .now,
            rules: rules,
            theses: theses,
            parameters: parameters,
            analysisSummary: limited(draft.summary, length: 600),
            theoryBasis: cleaned(draft.theoryBasis, limit: 8, itemLength: 300),
            marketContext: cleaned(draft.marketContext, limit: 8, itemLength: 300),
            sources: analysisSources(draft.sources),
            generatedBy: "Codex CLI · 实时搜索"
        )
    }

    private func applyCodexAdvice(_ draft: CodexAdviceDraft) {
        let sources = analysisSources(draft.sources)
        let sourceByURL = Dictionary(
            sources.map { ($0.url, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let holdingsBySymbol = Dictionary(
            portfolio.holdings.map { ($0.symbol.uppercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let marketContext = cleaned(draft.marketContext, limit: 2, itemLength: 300)
        let theoryBasis = cleaned(draft.theoryBasis, limit: 2, itemLength: 300)
        let now = Date.now

        let generated = draft.advice.prefix(8).enumerated().map { index, item -> AdviceItem in
            let symbol = item.relatedSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let relatedObject: String
            if let holding = holdingsBySymbol[symbol] {
                relatedObject = "\(holding.name) · \(holding.symbol)"
            } else if symbol.isEmpty {
                relatedObject = "组合"
            } else {
                relatedObject = symbol
            }

            var evidence = cleaned(item.evidence, limit: 6, itemLength: 300)
            if let context = marketContext.first { evidence.append("近期背景：\(context)") }
            if let theory = theoryBasis.first { evidence.append("理论依据：\(theory)") }
            let matchedSources = item.sourceUrls.compactMap { sourceByURL[$0] }
            let validDays = min(max(item.validDays, 1), 30)
            return AdviceItem(
                id: "codex:\(UUID().uuidString)",
                title: nonEmpty(item.title, fallback: "需要复核的投资事项"),
                summary: limited(item.summary, length: 500),
                relatedObject: relatedObject,
                trigger: limited(item.trigger, length: 300),
                evidence: evidence.isEmpty ? ["Codex 标记为待核验"] : evidence,
                counterEvidence: limited(item.counterEvidence, length: 500),
                priority: advicePriority(item.priority),
                status: .pending,
                confidence: "\(confidenceLabel(item.confidence))（Codex 综合分析）",
                createdAt: now.addingTimeInterval(TimeInterval(-index)),
                validUntil: Calendar.current.date(byAdding: .day, value: validDays, to: now) ?? now,
                sources: matchedSources,
                origin: .codex
            )
        }

        let localRules = advice.filter { $0.id.hasPrefix("strategy-rule:") }
        let codexHistory = advice.filter {
            $0.origin == .codex
                && $0.status != .pending
                && $0.status != .snoozed
        }
        advice = (generated + localRules + codexHistory).sorted { $0.createdAt > $1.createdAt }
    }

    private func analysisSources(_ drafts: [CodexSourceDraft]) -> [AnalysisSource] {
        var seen = Set<String>()
        return drafts.prefix(15).compactMap { draft in
            let url = draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !seen.contains(url),
                  let parsed = URL(string: url),
                  parsed.scheme?.lowercased() == "https",
                  parsed.host != nil else { return nil }
            seen.insert(url)
            return AnalysisSource(
                title: nonEmpty(draft.title, fallback: parsed.host ?? "公开来源"),
                publisher: nonEmpty(draft.publisher, fallback: parsed.host ?? "公开来源"),
                url: url,
                publishedAt: nonEmpty(draft.publishedAt, fallback: "日期待核验")
            )
        }
    }

    private func thesisHealth(_ value: String) -> ThesisHealth {
        switch value.lowercased() {
        case "supported": .supported
        case "missing": .missing
        default: .review
        }
    }

    private func advicePriority(_ value: String) -> AdvicePriority {
        switch value.lowercased() {
        case "high": .high
        case "low": .low
        default: .medium
        }
    }

    private func confidenceLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "high": "高"
        case "low": "低"
        default: "中"
        }
    }

    private func clamped(_ value: Double, minimum: Double, maximum: Double) -> Double {
        min(max(value.isFinite ? value : minimum, minimum), maximum)
    }

    private func percentageLimit(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1))))%"
    }

    private func nonEmpty(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func limited(_ value: String, length: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(length))
    }

    private func cleaned(_ values: [String], limit: Int, itemLength: Int) -> [String] {
        values.prefix(limit).compactMap { value in
            let text = limited(value, length: itemLength)
            return text.isEmpty ? nil : text
        }
    }

    private func persistPortfolio() {
        guard let database else {
            lastPersistenceError = "SQLite 数据库不可用，当前改动只保留在内存中。"
            return
        }
        do {
            try database.savePortfolio(portfolio)
            databaseStatus = .ready(database.fileURL.lastPathComponent)
            lastPersistenceError = nil
            refreshDatabaseStatistics()
            refreshRuleAdvice()
            persistLearningContextIfConnected()
        } catch {
            databaseStatus = .failed(error.localizedDescription)
            lastPersistenceError = error.localizedDescription
        }
    }

    func refreshRuleAdvice() {
        let prefix = "strategy-rule:"
        let existing = Dictionary(
            uniqueKeysWithValues: advice
                .filter { $0.id.hasPrefix(prefix) }
                .map { ($0.id, $0) }
        )
        let active = evaluatedStrategyRules.filter { $0.state != .healthy }
        let now = Date.now

        var generated = active.map { rule in
            let id = "\(prefix)\(rule.id)"
            let old = existing[id] ?? (rule.id == "single-position"
                ? advice.first { $0.id == "advice-concentration" }
                : nil)
            let isReopened = old?.status == .completed
            return AdviceItem(
                id: id,
                title: rule.state == .breached ? "策略规则已偏离：\(rule.title)" : "策略规则接近阈值：\(rule.title)",
                summary: rule.state == .breached
                    ? "当前组合已经超出你设置的纪律边界，请先核对数据和原始策略，再决定是否需要行动。"
                    : "当前值正在接近纪律边界，建议在下次复盘时检查，不因单日波动仓促交易。",
                relatedObject: "组合策略 · \(rule.title)",
                trigger: "当前 \(rule.currentValue)，策略边界 \(rule.limitValue)",
                evidence: [
                    "规则由本地组合数字确定性计算",
                    rule.description
                ],
                counterEvidence: "持仓价格和汇率变化会改变权重；采取任何行动前仍需核对最新数据、税费和投资论点。",
                priority: rule.state == .breached ? .high : .medium,
                status: isReopened ? .pending : (old?.status ?? .pending),
                confidence: "高（规则计算）",
                createdAt: isReopened ? now : (old?.createdAt ?? now),
                validUntil: Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now,
                sources: nil,
                origin: .localRule
            )
        }

        let activeIDs = Set(generated.map(\.id))
        generated.append(contentsOf: existing.values.compactMap { item in
            guard !activeIDs.contains(item.id) else { return nil }
            var resolved = item
            if resolved.status == .pending || resolved.status == .snoozed || resolved.status == .accepted {
                resolved.status = .completed
            }
            return resolved
        })

        let retained = advice.filter {
            !$0.id.hasPrefix(prefix) && $0.id != "advice-concentration"
        }
        advice = (generated + retained).sorted { $0.createdAt > $1.createdAt }
        persistWorkspaceContent()
    }

    private func persistWorkspaceContent() {
        guard let database else {
            lastPersistenceError = "SQLite 数据库不可用，策略与研究改动只保留在内存中。"
            return
        }
        do {
            try database.saveWorkspaceContent(
                WorkspaceContent(
                    strategy: strategy,
                    advice: advice,
                    schedules: schedules,
                    reports: reports
                )
            )
            databaseStatus = .ready(database.fileURL.lastPathComponent)
            lastPersistenceError = nil
        } catch {
            databaseStatus = .failed(error.localizedDescription)
            lastPersistenceError = error.localizedDescription
        }
    }

    private func refreshDatabaseStatistics() {
        guard let database else { return }
        databaseStatistics = try? database.statistics()
    }
}
