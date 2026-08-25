import Foundation
import Darwin

private struct RegressionFailure: Error, CustomStringConvertible {
    let description: String
}

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var lastFailure: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: RegressionFailure(description: "缺少网络桩"))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            Self.lastFailure = String(describing: error)
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private struct EmptyCredentialStore: GPTCredentialStoring {
    func save(apiKey: String) throws {}
    func loadAPIKey() throws -> String? { nil }
    func delete() throws {}
}

private struct FailingResearchProvider: GPTResearchProviding {
    func generateIndustryReport(
        schedule: ResearchSchedule,
        portfolio: PortfolioSnapshot,
        previousReport: IndustryReport?,
        evidence: [ResearchEvidence]
    ) async throws -> IndustryReport {
        throw ServiceError.notConfigured("测试研报服务")
    }
}

private struct DelayedResearchProvider: GPTResearchProviding {
    func generateIndustryReport(
        schedule: ResearchSchedule,
        portfolio: PortfolioSnapshot,
        previousReport: IndustryReport?,
        evidence: [ResearchEvidence]
    ) async throws -> IndustryReport {
        try await Task.sleep(for: .milliseconds(120))
        return IndustryReport(
            id: "delayed-report",
            title: "异步回归研报",
            industry: schedule.industryScope,
            executiveSummary: "测试",
            changes: ["测试一", "测试二"],
            portfolioImpact: "测试",
            counterEvidence: "测试",
            sources: ["本地测试"],
            periodStart: .now,
            periodEnd: .now,
            generatedAt: .now,
            modelName: "本地测试",
            isUnread: true
        )
    }
}

private struct StubCodexProvider: CodexInvestmentGenerating {
    private let source = CodexSourceDraft(
        title: "港股公开研究",
        publisher: "测试机构",
        url: "https://example.com/research",
        publishedAt: "2026-08-20"
    )

    func generateStrategy(context: CodexInvestmentContext) async throws -> CodexStrategyDraft {
        CodexStrategyDraft(
            summary: "结合当前组合和分散化理论形成的测试策略。",
            strategyName: "Codex 稳健策略",
            strategyDescription: "重视安全边际、现金缓冲和可复核论点。",
            riskProfile: "稳健 · 中低频",
            singlePositionWarningPercent: 22,
            singlePositionLimitPercent: 25,
            sectorWarningPercent: 32,
            sectorLimitPercent: 38,
            cashMinimumPercent: 12,
            cashWarningPercent: 15,
            theoryBasis: ["分散化降低非系统性风险", "安全边际约束估值风险"],
            marketContext: ["近期市场波动需要保留流动性"],
            theses: context.portfolio.holdings.filter { $0.assetType != .cash }.map {
                CodexThesisDraft(
                    symbol: $0.symbol,
                    companyName: $0.name,
                    summary: "测试持有逻辑",
                    keyEvidence: "测试证据",
                    invalidatingConditions: "测试失效条件",
                    nextReviewDays: 21,
                    health: "review"
                )
            },
            sources: [source]
        )
    }

    func generateAdvice(context: CodexInvestmentContext) async throws -> CodexAdviceDraft {
        CodexAdviceDraft(
            summary: "生成一条需要人工复核的测试建议。",
            marketContext: ["近期公开信息发生变化"],
            theoryBasis: ["安全边际", "仓位管理"],
            advice: [
                CodexAdviceItemDraft(
                    title: "复核核心持仓论点",
                    summary: "结合近期信息重新核对关键假设。",
                    relatedSymbol: context.portfolio.holdings.first?.symbol ?? "",
                    trigger: "近期信息与原论点需要交叉验证",
                    evidence: ["公开材料提供了新的验证点"],
                    counterEvidence: "单一来源可能不完整。",
                    priority: "high",
                    confidence: "medium",
                    validDays: 7,
                    sourceUrls: [source.url]
                )
            ],
            sources: [source]
        )
    }
}

@main
private struct CoreRegressionTests {
    private static var passed = 0
    private static var failed = 0

    static func main() async {
        await run("组合估值与现金口径", testPortfolioMath)
        await run("SQLite 迁移、往返与事务回滚", testDatabaseRoundTrip)
        await run("内置课程升级与用户进度保留", testLearningBootstrapUpgrade)
        await run("28 天课程与来源约束", testCurriculumAndSources)
        await run("交易账本更新持仓与现金", testTradeLedger)
        await run("研报调度日期", testScheduler)
        await run("研报失败退避与异步删除安全", testResearchTaskSafety)
        await run("OpenAI 严格输出与官方域名边界", testOpenAIRequestBoundary)
        await run("长桥组件超时降级", testLongbridgeTimeout)
        await run("Codex 策略建议应用与持久化", testCodexGenerationApplication)
        await run("Codex CLI 只读实时搜索边界", testCodexCLIInvocationBoundary)

        print("核心回归：\(passed) 通过，\(failed) 失败")
        if failed > 0 { Darwin.exit(1) }
    }

    private static func run(
        _ name: String,
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            passed += 1
            print("  ✓ \(name)")
        } catch {
            failed += 1
            print("  ✗ \(name)：\(error)")
        }
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else { throw RegressionFailure(description: message) }
    }

    private static func expectClose(
        _ actual: Double,
        _ expected: Double,
        accuracy: Double = 0.000_001,
        _ message: String
    ) throws {
        try expect(abs(actual - expected) <= accuracy, "\(message)，实际 \(actual)，期望 \(expected)")
    }

    private static func testPortfolioMath() async throws {
        let stock = Holding(
            id: "stock",
            symbol: "TEST.HK",
            name: "测试股票",
            assetType: .stock,
            sector: "科技",
            currency: "HKD",
            shares: 10,
            availableShares: 10,
            averageCost: 80,
            lastPrice: 100,
            dailyChangePercent: 2,
            source: .manual
        )
        let cashHolding = Holding(
            id: "cash",
            symbol: "BANK-CASH",
            name: "银行现金",
            assetType: .cash,
            sector: "现金",
            currency: "HKD",
            shares: 500,
            availableShares: 500,
            averageCost: 0,
            lastPrice: 1,
            dailyChangePercent: 9,
            source: .manual
        )
        let portfolio = PortfolioSnapshot(
            holdings: [stock, cashHolding],
            cash: 200,
            currency: "HKD",
            updatedAt: .now
        )

        try expectClose(cashHolding.totalProfit, 0, "现金不能被计为投资收益")
        try expectClose(cashHolding.estimatedDailyProfit, 0, "现金不能产生证券日收益")
        try expectClose(portfolio.totalAssets, 1_700, "总资产口径错误")
        try expectClose(portfolio.totalCash, 700, "总现金口径错误")
        try expectClose(portfolio.totalProfit, 200, "组合盈亏不应包含现金")
    }

    private static func testDatabaseRoundTrip() async throws {
        let (directory, database) = try makeTemporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }

        let holding = Holding(
            id: "manual-fund",
            symbol: "FUND-1",
            name: "测试基金",
            assetType: .fund,
            sector: "多资产",
            currency: "CNY",
            shares: 100,
            availableShares: 100,
            averageCost: 1.2,
            lastPrice: 1.3,
            dailyChangePercent: 0.5,
            exchangeRateToBase: 1.08,
            source: .manual,
            note: "往返测试"
        )
        let initial = PortfolioSnapshot(
            holdings: [holding],
            cash: 1_000,
            currency: "HKD",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try database.savePortfolio(initial)
        let loaded = try database.loadPortfolio()
        try expect(loaded?.holdings.count == 1, "持仓 SQLite 往返数量错误")
        try expect(loaded?.holdings.first?.id == holding.id, "持仓 SQLite 往返标识错误")
        try expect(loaded?.holdings.first?.assetType == holding.assetType, "持仓 SQLite 往返类型错误")
        try expectClose(loaded?.holdings.first?.shares ?? -1, holding.shares, "持仓 SQLite 往返数量错误")
        try expectClose(loaded?.holdings.first?.lastPrice ?? -1, holding.lastPrice, "持仓 SQLite 往返价格错误")
        try expectClose(loaded?.cash ?? -1, 1_000, "现金 SQLite 往返失败")

        let payload = PreviewData.workspace()
        let legacySchedule = ResearchSchedule(
            id: "legacy",
            name: "旧任务",
            industryScope: "科技",
            template: .weekly,
            nextRunAt: .now,
            lastRunAt: nil,
            isEnabled: true,
            state: .ready,
            modelName: "本地模拟",
            monthlyBudget: 100,
            institutionSources: nil
        )
        try database.saveWorkspaceContent(
            WorkspaceContent(
                strategy: payload.strategy,
                advice: payload.advice,
                schedules: [legacySchedule],
                reports: payload.reports
            )
        )
        let workspace = try database.loadWorkspaceContent()
        try expect(
            workspace?.schedules.first?.selectedInstitutionSources.count == InstitutionResearchSource.allCases.count,
            "旧任务缺少机构字段时必须兼容为全部官方来源"
        )

        let trade = RecordedTrade(
            id: "trade-atomic",
            holdingID: holding.id,
            symbol: holding.symbol,
            name: holding.name,
            assetType: holding.assetType,
            side: .buy,
            quantity: 1,
            price: 1.3,
            fees: 0,
            currency: "CNY",
            exchangeRateToBase: 1.08,
            tradedAt: .now,
            note: "",
            createdAt: .now
        )
        let firstUpdate = PortfolioSnapshot(
            holdings: [holding],
            cash: 900,
            currency: "HKD",
            updatedAt: .now
        )
        try database.recordTrade(trade, updatedPortfolio: firstUpdate)
        let invalidSecondUpdate = PortfolioSnapshot(
            holdings: [],
            cash: 1,
            currency: "HKD",
            updatedAt: .now
        )
        do {
            try database.recordTrade(trade, updatedPortfolio: invalidSecondUpdate)
            throw RegressionFailure(description: "重复交易 ID 应失败")
        } catch is RegressionFailure {
            throw RegressionFailure(description: "重复交易 ID 没有触发数据库约束")
        } catch {
            // Expected: the duplicate trade rolls the entire transaction back.
        }
        try expectClose(try database.loadPortfolio()?.cash ?? -1, 900, "交易失败后组合必须回滚")
        let statistics = try database.statistics()
        try expect(statistics.tradeCount == 1, "重复交易不能写入账本")
    }

    private static func testLearningBootstrapUpgrade() async throws {
        let (directory, database) = try makeTemporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = LearningCurriculum.units[0]
        try database.bootstrapLearning(
            units: [original],
            settings: .default,
            methodology: LearningCurriculum.defaultMethodology
        )
        var progress = LessonProgress.empty(for: original.id)
        progress.status = .completed
        progress.confidence = 4
        progress.completedAt = .now
        progress.updatedAt = .now
        try database.saveLessonProgress(progress)

        let updated = copyLesson(original, title: "升级后的课程标题", source: .builtIn)
        try database.bootstrapLearning(
            units: [updated],
            settings: .default,
            methodology: LearningCurriculum.defaultMethodology
        )
        var state = try database.loadLearningState()
        try expect(state.units.first?.title == updated.title, "已有数据库没有刷新内置课程")
        try expect(state.progress[original.id]?.status == .completed, "课程升级丢失了学习进度")

        let generated = copyLesson(updated, title: "Codex 自定义课程", source: .codex)
        try database.saveLearningUnit(generated)
        try database.bootstrapLearning(
            units: [updated],
            settings: .default,
            methodology: LearningCurriculum.defaultMethodology
        )
        state = try database.loadLearningState()
        try expect(state.units.first?.title == generated.title, "启动时不应覆盖 Codex 自定义课程")
    }

    private static func testCurriculumAndSources() async throws {
        let units = LearningCurriculum.units
        try expect(units.count == 28, "课程必须压缩为 28 天")
        try expect(Set(units.map(\.id)).count == 28, "课程 ID 必须唯一")
        try expect(Set(units.map(\.day)).count == 28, "课程天数必须唯一")
        try expect(units.allSatisfy { (1...4).contains($0.week) }, "课程周数超出 4 周")
        try expect(
            units.flatMap(\.quiz).allSatisfy { $0.correctIndex >= 0 && $0.correctIndex < $0.options.count },
            "测验正确答案索引越界"
        )
        try expect(
            LearningCurriculum.investorProfiles.count >= 3,
            "投资人方法至少应覆盖巴菲特、芒格和段永平"
        )
        try expect(
            LearningCurriculum.investorProfiles.flatMap(\.sources).allSatisfy {
                $0.linkURL?.scheme == "https"
            },
            "投资人学习来源必须使用 HTTPS"
        )
        try expect(
            InstitutionResearchSource.allCases.allSatisfy {
                $0.portalURL.scheme == "https" && $0.portalURL.host?.hasSuffix($0.domain) == true
            },
            "机构入口必须落在声明的官方域名"
        )
    }

    @MainActor
    private static func testTradeLedger() async throws {
        let (_, database) = try makeTemporaryDatabase()
        let manual = Holding(
            id: "manual-stock",
            symbol: "MANUAL",
            name: "手动股票",
            assetType: .stock,
            sector: "科技",
            currency: "HKD",
            shares: 10,
            availableShares: 10,
            averageCost: 100,
            lastPrice: 100,
            dailyChangePercent: 0,
            source: .manual
        )
        let cashHolding = Holding(
            id: "manual-cash",
            symbol: "CASH",
            name: "现金账户",
            assetType: .cash,
            sector: "现金",
            currency: "HKD",
            shares: 5_000,
            availableShares: 5_000,
            averageCost: 0,
            lastPrice: 1,
            dailyChangePercent: 0,
            source: .manual
        )
        let preview = PreviewData.workspace()
        let payload = WorkspacePayload(
            portfolio: PortfolioSnapshot(
                holdings: [manual, cashHolding],
                cash: 1_000,
                currency: "HKD",
                updatedAt: .now
            ),
            strategy: preview.strategy,
            advice: preview.advice,
            schedules: preview.schedules,
            reports: preview.reports
        )
        let model = AppModel(database: database, initialPayload: payload)
        try expect(model.largestHolding?.id == manual.id, "现金不能成为最大证券持仓")
        try expect(model.sectorAllocations.allSatisfy { $0.sector != "现金" }, "现金不能进入行业集中度")

        let buy = RecordedTrade(
            id: "buy",
            holdingID: manual.id,
            symbol: manual.symbol,
            name: manual.name,
            assetType: manual.assetType,
            side: .buy,
            quantity: 5,
            price: 120,
            fees: 5,
            currency: "HKD",
            exchangeRateToBase: 1,
            tradedAt: .now,
            note: "",
            createdAt: .now
        )
        try expect(model.recordTrade(buy, applyToPosition: true, applyToCash: true), "买入交易保存失败")
        let updated = model.portfolio.holdings.first { $0.id == manual.id }
        try expectClose(updated?.shares ?? -1, 15, "买入后数量错误")
        try expectClose(updated?.averageCost ?? -1, 107, "买入后平均成本错误")
        try expectClose(model.portfolio.cash, 395, "买入后现金错误")

        let invalidSell = RecordedTrade(
            id: "invalid-sell",
            holdingID: manual.id,
            symbol: manual.symbol,
            name: manual.name,
            assetType: manual.assetType,
            side: .sell,
            quantity: 20,
            price: 130,
            fees: 0,
            currency: "HKD",
            exchangeRateToBase: 1,
            tradedAt: .now,
            note: "",
            createdAt: .now
        )
        try expect(!model.recordTrade(invalidSell, applyToPosition: true, applyToCash: true), "超额卖出必须被拒绝")
        let statistics = try database.statistics()
        try expect(statistics.tradeCount == 1, "被拒绝的卖出不能写入账本")
    }

    private static func testScheduler() async throws {
        let scheduler = ResearchScheduler()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let daily = await scheduler.nextRun(after: start, template: .closeBrief)
        let weekly = await scheduler.nextRun(after: start, template: .weekly)
        let monthly = await scheduler.nextRun(after: start, template: .monthly)
        try expectClose(daily.timeIntervalSince(start), 86_400, "收盘简报间隔错误")
        try expectClose(weekly.timeIntervalSince(start), 604_800, "周报间隔错误")
        try expect(monthly > weekly, "月报下一次运行时间错误")
    }

    @MainActor
    private static func testResearchTaskSafety() async throws {
        let preview = PreviewData.workspace()
        let dueSchedule = ResearchSchedule(
            id: "due-schedule",
            name: "失败退避测试",
            industryScope: "科技",
            template: .weekly,
            nextRunAt: Date(timeIntervalSinceNow: -60),
            lastRunAt: nil,
            isEnabled: true,
            state: .ready,
            modelName: "本地测试",
            monthlyBudget: 100,
            institutionSources: [.morganStanley]
        )
        let failedPayload = WorkspacePayload(
            portfolio: preview.portfolio,
            strategy: preview.strategy,
            advice: preview.advice,
            schedules: [dueSchedule],
            reports: []
        )
        let (_, failedDatabase) = try makeTemporaryDatabase()
        let failedModel = AppModel(
            researchService: FailingResearchProvider(),
            gptKeychain: EmptyCredentialStore(),
            database: failedDatabase,
            initialPayload: failedPayload
        )
        let failureStartedAt = Date()
        await failedModel.runSchedule(dueSchedule)
        let failedSchedule = failedModel.schedules.first
        try expect(failedSchedule?.state == .failed, "失败任务状态错误")
        try expect(
            (failedSchedule?.nextRunAt.timeIntervalSince(failureStartedAt) ?? 0) > 3_500,
            "失败任务没有退避，可能每 15 分钟重复消耗 API"
        )

        let deleteSchedule = ResearchSchedule(
            id: "delete-during-run",
            name: "异步删除测试",
            industryScope: "金融",
            template: .weekly,
            nextRunAt: .now,
            lastRunAt: nil,
            isEnabled: true,
            state: .ready,
            modelName: "本地测试",
            monthlyBudget: 100,
            institutionSources: [.bridgewater]
        )
        let deletePayload = WorkspacePayload(
            portfolio: preview.portfolio,
            strategy: preview.strategy,
            advice: preview.advice,
            schedules: [deleteSchedule],
            reports: []
        )
        let (_, deleteDatabase) = try makeTemporaryDatabase()
        let deleteModel = AppModel(
            researchService: DelayedResearchProvider(),
            gptKeychain: EmptyCredentialStore(),
            database: deleteDatabase,
            initialPayload: deletePayload
        )
        let runTask = Task { await deleteModel.runSchedule(deleteSchedule) }
        try await Task.sleep(for: .milliseconds(25))
        deleteModel.deleteSchedule(deleteSchedule)
        await runTask.value
        try expect(deleteModel.schedules.isEmpty, "生成期间删除的任务被错误恢复")
        try expect(deleteModel.reports.first?.id == "delayed-report", "已完成研报应保留在历史中")
    }

    private static func testOpenAIRequestBoundary() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let endpoint = URL(string: "https://unit.test/responses")!

        StubURLProtocol.handler = { request in
            let body = try expectJSONObject(requestBodyData(request))
            try expect(body["store"] as? Bool == false, "Responses API 必须禁用存储")
            let tools = try expectArray(body["tools"])
            let tool = try expectDictionary(tools.first)
            let filters = try expectDictionary(tool["filters"])
            let domains = try expectStringArray(filters["allowed_domains"])
            try expect(domains == [InstitutionResearchSource.morganStanley.domain], "Web Search 域名白名单错误")

            let draft: [String: Any] = [
                "title": "测试研报",
                "executive_summary": "仅用于回归测试",
                "changes": ["变化一", "变化二"],
                "portfolio_impact": "待核验",
                "counter_evidence": "证据不足"
            ]
            let draftData = try JSONSerialization.data(withJSONObject: draft)
            let responseObject: [String: Any] = [
                "status": "completed",
                "output": [
                    [
                        "type": "web_search_call",
                        "action": [
                            "type": "search",
                            "sources": [
                                ["type": "url", "url": "https://www.morganstanley.com/insights/test", "title": "官方材料"],
                                ["type": "url", "url": "https://evil.example/fake", "title": "伪造材料"]
                            ]
                        ]
                    ],
                    [
                        "type": "message",
                        "content": [[
                            "type": "output_text",
                            "text": String(decoding: draftData, as: UTF8.self)
                        ]]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: responseObject)
            let response = HTTPURLResponse(
                url: endpoint,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }
        defer { StubURLProtocol.handler = nil }

        let service = OpenAIResearchService(
            apiKey: "unit-test-key",
            model: "test-model",
            endpoint: endpoint,
            session: session
        )
        let schedule = ResearchSchedule(
            id: "openai-test",
            name: "官方来源边界",
            industryScope: "科技",
            template: .weekly,
            nextRunAt: .now,
            lastRunAt: nil,
            isEnabled: true,
            state: .ready,
            modelName: "test-model",
            monthlyBudget: 100,
            institutionSources: [.morganStanley]
        )
        let report: IndustryReport
        do {
            report = try await service.generateIndustryReport(
                schedule: schedule,
                portfolio: PreviewData.workspace().portfolio,
                previousReport: nil,
                evidence: []
            )
        } catch {
            throw RegressionFailure(
                description: "OpenAI 网络桩失败：\(StubURLProtocol.lastFailure ?? error.localizedDescription)"
            )
        }
        try expect(report.sources.contains { $0.contains("morganstanley.com") }, "官方来源没有保存到研报")
        try expect(!report.sources.contains { $0.contains("evil.example") }, "白名单外来源进入了研报")
    }

    private static func testLongbridgeTimeout() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIInvestLongbridgeTimeout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("longbridge")
        try Data("#!/bin/sh\nexec /bin/sleep 5\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let defaults = UserDefaults.standard
        let key = "longbridge.executablePath"
        let previous = defaults.string(forKey: key)
        defaults.set(executable.path, forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) }
        }

        let startedAt = Date()
        let client = LongbridgeCLIClient(commandTimeout: .milliseconds(120))
        let state = await client.connectionStatus()
        let elapsed = Date().timeIntervalSince(startedAt)
        guard case .failed(let message) = state else {
            throw RegressionFailure(description: "超时命令没有进入失败状态")
        }
        try expect(message.contains("超时"), "超时错误没有可理解的提示")
        try expect(elapsed < 2, "超时降级耗时过长：\(elapsed) 秒")
    }

    @MainActor
    private static func testCodexGenerationApplication() async throws {
        let (directory, database) = try makeTemporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }
        let holding = Holding(
            id: "codex-holding",
            symbol: "CODX.HK",
            name: "Codex 测试持仓",
            assetType: .stock,
            sector: "科技",
            currency: "HKD",
            shares: 100,
            availableShares: 100,
            averageCost: 80,
            lastPrice: 100,
            dailyChangePercent: 0,
            source: .manual
        )
        let preview = PreviewData.workspace()
        let payload = WorkspacePayload(
            portfolio: PortfolioSnapshot(
                holdings: [holding],
                cash: 10_000,
                currency: "HKD",
                updatedAt: .now
            ),
            strategy: preview.strategy,
            advice: preview.advice,
            schedules: preview.schedules,
            reports: preview.reports
        )
        let model = AppModel(
            codexInvestmentService: StubCodexProvider(),
            database: database,
            initialPayload: payload
        )

        await model.generateStrategyWithCodex()
        try expect(model.strategy.name == "Codex 稳健策略", "Codex 策略没有应用")
        try expect(model.strategy.parameters?.singlePositionLimitPercent == 25, "Codex 策略阈值没有保存")
        try expect(model.strategy.theses.map(\.symbol) == [holding.symbol], "策略论点没有与当前持仓对齐")
        try expect(model.strategy.generatedBy?.contains("Codex CLI") == true, "策略缺少 Codex 来源标记")
        try expect(model.strategy.sources?.first?.linkURL != nil, "策略公开来源无效")

        await model.generateAdviceWithCodex()
        let generated = model.advice.first { $0.origin == .codex }
        try expect(generated?.title == "复核核心持仓论点", "Codex 建议没有应用")
        try expect(generated?.sources?.first?.url == "https://example.com/research", "Codex 建议没有保存来源")
        try expect(!model.advice.contains { $0.id == "advice-aia-thesis" }, "旧演示建议没有在生成后清理")
        try expect(model.advice.contains { $0.id.hasPrefix("strategy-rule:") }, "Codex 生成不应删除本地规则建议")

        let stored = try database.loadWorkspaceContent()
        try expect(stored?.strategy.generatedBy?.contains("Codex CLI") == true, "Codex 策略没有持久化")
        try expect(stored?.advice.contains { $0.origin == .codex } == true, "Codex 建议没有持久化")
    }

    private static func testCodexCLIInvocationBoundary() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIInvestCodexBoundary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fixtureURL = directory.appendingPathComponent("fixture.json")
        let argumentsURL = directory.appendingPathComponent("arguments.log")
        let promptURL = directory.appendingPathComponent("prompt.txt")
        let schemaURL = directory.appendingPathComponent("schema.json")
        let source: [String: Any] = [
            "title": "测试来源",
            "publisher": "测试机构",
            "url": "https://example.com/current",
            "published_at": "2026-08-20"
        ]
        let adviceItems: [[String: Any]] = (1...3).map { index in
            [
                "title": "建议 \(index)",
                "summary": "用于验证结构化输出",
                "related_symbol": "700.HK",
                "trigger": "测试触发",
                "evidence": ["测试证据"],
                "counter_evidence": "测试反面证据",
                "priority": "medium",
                "confidence": "medium",
                "valid_days": 7,
                "source_urls": ["https://example.com/current"]
            ]
        }
        let fixture: [String: Any] = [
            "summary": "测试摘要",
            "market_context": ["测试市场背景"],
            "theory_basis": ["分散化", "安全边际"],
            "advice": adviceItems,
            "sources": [source]
        ]
        try JSONSerialization.data(withJSONObject: fixture).write(to: fixtureURL)

        let executable = directory.appendingPathComponent("codex")
        let script = """
        #!/bin/sh
        printf '%s\n' "$*" >> '\(argumentsURL.path)'
        output=''
        schema=''
        previous=''
        for argument in "$@"; do
          if [ "$previous" = "--output-last-message" ]; then output="$argument"; fi
          if [ "$previous" = "--output-schema" ]; then schema="$argument"; fi
          previous="$argument"
        done
        if [ -n "$output" ]; then
          /bin/cat > '\(promptURL.path)'
          /bin/cp "$schema" '\(schemaURL.path)'
          /bin/cp '\(fixtureURL.path)' "$output"
        fi
        exit 0
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let preview = PreviewData.workspace()
        let context = CodexInvestmentContext(
            portfolio: preview.portfolio,
            strategy: preview.strategy,
            evaluatedRules: preview.strategy.rules,
            recentReports: preview.reports,
            dataMode: .preview
        )
        let client = CodexCLIClient(executableURL: executable, commandTimeout: .seconds(2))
        let draft = try await client.generateAdvice(context: context)
        try expect(draft.advice.count == 3, "Codex CLI 结构化结果解析失败")

        let arguments = try String(contentsOf: argumentsURL)
        try expect(arguments.contains("--search"), "Codex CLI 没有启用实时搜索")
        try expect(arguments.contains("--sandbox read-only"), "Codex CLI 没有使用只读沙盒")
        try expect(arguments.contains("--ask-for-approval never"), "Codex CLI 可能等待不可见审批")
        try expect(arguments.contains("--ephemeral"), "Codex CLI 没有使用临时会话")
        try expect(arguments.contains("--ignore-user-config"), "Codex CLI 不应加载用户插件或自定义工具配置")
        try expect(arguments.contains("--output-schema"), "Codex CLI 缺少结构化输出约束")

        let prompt = try String(contentsOf: promptURL)
        try expect(prompt.contains("实时 web search"), "Codex 提示没有要求近期信息检索")
        try expect(prompt.contains("700.HK"), "Codex 提示缺少持仓上下文")
        try expect(!prompt.lowercased().contains("average_cost"), "Codex 提示不应发送成本字段")

        let schemaData = try Data(contentsOf: schemaURL)
        let schemaObject = try JSONSerialization.jsonObject(with: schemaData) as? [String: Any]
        try expect(schemaObject?["type"] as? String == "object", "Codex 输出 Schema 不是有效 JSON 对象")
    }

    private static func makeTemporaryDatabase() throws -> (URL, InvestmentDatabase) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIInvestCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try InvestmentDatabase(fileURL: directory.appendingPathComponent("test.sqlite"))
        return (directory, database)
    }

    private static func copyLesson(
        _ unit: LearningUnit,
        title: String,
        source: LessonSource
    ) -> LearningUnit {
        LearningUnit(
            id: unit.id,
            week: unit.week,
            day: unit.day,
            track: unit.track,
            title: title,
            objective: unit.objective,
            summary: unit.summary,
            keyPoints: unit.keyPoints,
            example: unit.example,
            exercise: unit.exercise,
            quiz: unit.quiz,
            reviewQuestions: unit.reviewQuestions,
            suggestedCodexQuestions: unit.suggestedCodexQuestions,
            source: source,
            generatedAt: source == .codex ? .now : nil
        )
    }

    private static func expectJSONObject(_ data: Data?) throws -> [String: Any] {
        guard let data,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RegressionFailure(description: "请求体不是 JSON 对象")
        }
        return object
    }

    private static func requestBodyData(_ request: URLRequest) throws -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? RegressionFailure(description: "无法读取请求体") }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private static func expectArray(_ value: Any?) throws -> [Any] {
        guard let value = value as? [Any] else {
            throw RegressionFailure(description: "期望 JSON 数组")
        }
        return value
    }

    private static func expectDictionary(_ value: Any?) throws -> [String: Any] {
        guard let value = value as? [String: Any] else {
            throw RegressionFailure(description: "期望 JSON 对象")
        }
        return value
    }

    private static func expectStringArray(_ value: Any?) throws -> [String] {
        guard let value = value as? [String] else {
            throw RegressionFailure(description: "期望字符串数组")
        }
        return value
    }
}
