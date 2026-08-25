import Foundation

enum AppSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case holdings = "持仓"
    case strategy = "策略"
    case advice = "建议"
    case research = "行业研报"
    case learning = "学习"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .holdings: "chart.pie.fill"
        case .strategy: "scope"
        case .advice: "sparkles"
        case .research: "doc.text.magnifyingglass"
        case .learning: "graduationcap.fill"
        }
    }
}

enum AssetType: String, CaseIterable, Identifiable, Codable, Sendable {
    case stock = "股票"
    case fund = "基金"
    case etf = "ETF"
    case crypto = "加密货币"
    case bond = "债券"
    case cash = "现金"
    case other = "其他"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .stock: "chart.line.uptrend.xyaxis"
        case .fund: "square.stack.3d.up.fill"
        case .etf: "chart.pie.fill"
        case .crypto: "bitcoinsign.circle.fill"
        case .bond: "doc.text.fill"
        case .cash: "banknote.fill"
        case .other: "shippingbox.fill"
        }
    }
}

enum HoldingSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case longbridge = "长桥同步"
    case manual = "手动录入"

    var id: String { rawValue }
}

enum TradeSide: String, CaseIterable, Identifiable, Codable, Sendable {
    case buy = "买入"
    case sell = "卖出"

    var id: String { rawValue }
}

struct RecordedTrade: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let holdingID: String?
    let symbol: String
    let name: String
    let assetType: AssetType
    let side: TradeSide
    let quantity: Double
    let price: Double
    let fees: Double
    let currency: String
    let exchangeRateToBase: Double
    let tradedAt: Date
    let note: String
    let createdAt: Date

    var grossAmount: Double { quantity * price }
    var grossAmountInBase: Double { grossAmount * exchangeRateToBase }
    var feesInBase: Double { fees * exchangeRateToBase }
    var cashImpactInBase: Double {
        switch side {
        case .buy: -(grossAmountInBase + feesInBase)
        case .sell: grossAmountInBase - feesInBase
        }
    }
}

struct DatabaseStatistics: Equatable, Sendable {
    let holdingCount: Int
    let pricePointCount: Int
    let tradeCount: Int
    let cashSnapshotCount: Int
    let learningUnitCount: Int
    let completedLessonCount: Int
    let learningNoteCount: Int
}

enum DatabaseStatus: Equatable, Sendable {
    case ready(String)
    case failed(String)

    var label: String {
        switch self {
        case .ready: "SQLite 已连接"
        case .failed: "SQLite 不可用"
        }
    }
}

struct Holding: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var symbol: String
    var name: String
    var assetType: AssetType
    var sector: String
    var currency: String
    var shares: Double
    var availableShares: Double
    var averageCost: Double
    var lastPrice: Double
    var dailyChangePercent: Double
    var exchangeRateToBase: Double
    var source: HoldingSource
    var note: String
    var updatedAt: Date

    init(
        id: String? = nil,
        symbol: String,
        name: String,
        assetType: AssetType = .stock,
        sector: String,
        currency: String,
        shares: Double,
        availableShares: Double,
        averageCost: Double,
        lastPrice: Double,
        dailyChangePercent: Double,
        exchangeRateToBase: Double = 1,
        source: HoldingSource = .longbridge,
        note: String = "",
        updatedAt: Date = .now
    ) {
        self.id = id ?? "\(source.rawValue):\(symbol)"
        self.symbol = symbol
        self.name = name
        self.assetType = assetType
        self.sector = sector
        self.currency = currency
        self.shares = shares
        self.availableShares = availableShares
        self.averageCost = averageCost
        self.lastPrice = lastPrice
        self.dailyChangePercent = dailyChangePercent
        self.exchangeRateToBase = exchangeRateToBase
        self.source = source
        self.note = note
        self.updatedAt = updatedAt
    }

    /// Native-currency value before conversion to the portfolio base currency.
    var nativeMarketValue: Double { shares * lastPrice }
    var marketValue: Double { nativeMarketValue * exchangeRateToBase }
    /// Cash is already denominated at its current value. Treating a zero-cost cash
    /// entry as profit would overstate both P&L and the strategy signals built on it.
    var costBasis: Double {
        assetType == .cash ? marketValue : shares * averageCost * exchangeRateToBase
    }
    var totalProfit: Double { assetType == .cash ? 0 : marketValue - costBasis }
    var totalProfitPercent: Double { costBasis == 0 ? 0 : totalProfit / costBasis * 100 }
    var estimatedDailyProfit: Double {
        assetType == .cash ? 0 : marketValue * dailyChangePercent / 100
    }
}

struct PortfolioSnapshot: Sendable {
    let holdings: [Holding]
    let cash: Double
    let currency: String
    let updatedAt: Date

    var holdingsValue: Double { holdings.reduce(0) { $0 + $1.marketValue } }
    var manualCashValue: Double {
        holdings.filter { $0.assetType == .cash }.reduce(0) { $0 + $1.marketValue }
    }
    var totalCash: Double { cash + manualCashValue }
    var totalAssets: Double { holdingsValue + cash }
    var totalCost: Double { holdings.reduce(0) { $0 + $1.costBasis } }
    var totalProfit: Double { holdingsValue - totalCost }
    var dailyProfit: Double { holdings.reduce(0) { $0 + $1.estimatedDailyProfit } }
    var cashWeight: Double { totalAssets == 0 ? 0 : totalCash / totalAssets }
}

struct SectorAllocation: Identifiable, Hashable, Sendable {
    let sector: String
    let marketValue: Double

    var id: String { sector }
}

enum RuleState: String, Codable, Sendable {
    case healthy = "正常"
    case warning = "接近阈值"
    case breached = "已偏离"
}

struct StrategyRule: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let description: String
    let currentValue: String
    let limitValue: String
    let state: RuleState
}

enum ThesisHealth: String, Codable, Sendable {
    case supported = "论点有效"
    case review = "需要复核"
    case missing = "待补充"
}

struct InvestmentThesis: Identifiable, Hashable, Codable, Sendable {
    let symbol: String
    let companyName: String
    let summary: String
    let keyEvidence: String
    let nextReviewAt: Date
    let health: ThesisHealth

    var id: String { symbol }
}

struct AnalysisSource: Identifiable, Hashable, Codable, Sendable {
    let title: String
    let publisher: String
    let url: String
    let publishedAt: String

    var id: String { url }

    var linkURL: URL? {
        guard let candidate = URL(string: url),
              candidate.scheme?.lowercased() == "https",
              candidate.host != nil else { return nil }
        return candidate
    }
}

struct StrategyParameters: Hashable, Codable, Sendable {
    let singlePositionWarningPercent: Double
    let singlePositionLimitPercent: Double
    let sectorWarningPercent: Double
    let sectorLimitPercent: Double
    let cashMinimumPercent: Double
    let cashWarningPercent: Double

    static let steadyDefault = StrategyParameters(
        singlePositionWarningPercent: 27,
        singlePositionLimitPercent: 30,
        sectorWarningPercent: 36,
        sectorLimitPercent: 40,
        cashMinimumPercent: 10,
        cashWarningPercent: 12
    )
}

struct InvestmentStrategy: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let description: String
    let riskProfile: String
    let updatedAt: Date
    let rules: [StrategyRule]
    let theses: [InvestmentThesis]
    /// Optional fields keep workspaces saved by earlier app versions decodable.
    let parameters: StrategyParameters?
    let analysisSummary: String?
    let theoryBasis: [String]?
    let marketContext: [String]?
    let sources: [AnalysisSource]?
    let generatedBy: String?

    init(
        id: String,
        name: String,
        description: String,
        riskProfile: String,
        updatedAt: Date,
        rules: [StrategyRule],
        theses: [InvestmentThesis],
        parameters: StrategyParameters? = nil,
        analysisSummary: String? = nil,
        theoryBasis: [String]? = nil,
        marketContext: [String]? = nil,
        sources: [AnalysisSource]? = nil,
        generatedBy: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.riskProfile = riskProfile
        self.updatedAt = updatedAt
        self.rules = rules
        self.theses = theses
        self.parameters = parameters
        self.analysisSummary = analysisSummary
        self.theoryBasis = theoryBasis
        self.marketContext = marketContext
        self.sources = sources
        self.generatedBy = generatedBy
    }
}

enum AdvicePriority: String, CaseIterable, Codable, Sendable {
    case high = "高"
    case medium = "中"
    case low = "低"
}

enum AdviceStatus: String, CaseIterable, Codable, Sendable {
    case pending = "待处理"
    case accepted = "已接受"
    case snoozed = "稍后提醒"
    case completed = "已完成"
    case ignored = "已忽略"
}

enum AdviceOrigin: String, Codable, Sendable {
    case localRule = "本地规则"
    case codex = "Codex CLI"
    case legacy = "早期内容"
}

struct AdviceItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let summary: String
    let relatedObject: String
    let trigger: String
    let evidence: [String]
    let counterEvidence: String
    let priority: AdvicePriority
    var status: AdviceStatus
    let confidence: String
    let createdAt: Date
    let validUntil: Date
    /// Optional fields keep advice saved by earlier app versions decodable.
    let sources: [AnalysisSource]?
    let origin: AdviceOrigin?

    init(
        id: String,
        title: String,
        summary: String,
        relatedObject: String,
        trigger: String,
        evidence: [String],
        counterEvidence: String,
        priority: AdvicePriority,
        status: AdviceStatus,
        confidence: String,
        createdAt: Date,
        validUntil: Date,
        sources: [AnalysisSource]? = nil,
        origin: AdviceOrigin? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.relatedObject = relatedObject
        self.trigger = trigger
        self.evidence = evidence
        self.counterEvidence = counterEvidence
        self.priority = priority
        self.status = status
        self.confidence = confidence
        self.createdAt = createdAt
        self.validUntil = validUntil
        self.sources = sources
        self.origin = origin
    }
}

enum CodexGenerationScope: String, Equatable, Sendable {
    case strategy = "策略"
    case advice = "建议"
}

enum ReportTemplate: String, CaseIterable, Identifiable, Codable, Sendable {
    case closeBrief = "交易日收盘简报"
    case weekly = "每周行业研报"
    case monthly = "月度深度跟踪"

    var id: String { rawValue }
}

enum ScheduleRunState: String, Codable, Sendable {
    case ready = "等待运行"
    case running = "生成中"
    case succeeded = "已完成"
    case failed = "运行失败"
    case waitingForData = "等待数据"
}

enum InstitutionResearchSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case morganStanley = "Morgan Stanley（大摩）"
    case bridgewater = "Bridgewater（桥水）"
    case goldmanSachs = "Goldman Sachs（高盛）"
    case jpmorgan = "J.P. Morgan（摩根大通）"

    var id: String { rawValue }

    var organizationKind: String {
        switch self {
        case .bridgewater: "全球资产管理机构"
        case .morganStanley, .goldmanSachs, .jpmorgan: "华尔街投行研究"
        }
    }

    var domain: String {
        switch self {
        case .morganStanley: "morganstanley.com"
        case .bridgewater: "bridgewater.com"
        case .goldmanSachs: "goldmansachs.com"
        case .jpmorgan: "jpmorgan.com"
        }
    }

    var portalURL: URL {
        switch self {
        case .morganStanley: URL(string: "https://www.morganstanley.com/insights/")!
        case .bridgewater: URL(string: "https://www.bridgewater.com/research-and-insights")!
        case .goldmanSachs: URL(string: "https://www.goldmansachs.com/insights/goldman-sachs-research")!
        case .jpmorgan: URL(string: "https://www.jpmorgan.com/insights/research")!
        }
    }

    var focus: String {
        switch self {
        case .morganStanley: "公司、行业、市场与全球经济"
        case .bridgewater: "宏观范式、资产配置与组合韧性"
        case .goldmanSachs: "宏观、市场、行业与主题研究"
        case .jpmorgan: "全球市场、经济与行业研究"
        }
    }
}

struct ResearchSchedule: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var industryScope: String
    var template: ReportTemplate
    var nextRunAt: Date
    var lastRunAt: Date?
    var isEnabled: Bool
    var state: ScheduleRunState
    var modelName: String
    var monthlyBudget: Double
    /// Optional keeps schedules saved by earlier app versions decodable.
    var institutionSources: [InstitutionResearchSource]? = nil

    var selectedInstitutionSources: [InstitutionResearchSource] {
        institutionSources ?? InstitutionResearchSource.allCases
    }
}

struct ResearchEvidence: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let excerpt: String
    let sourceName: String
    let publishedAt: String
    let url: String

    var sourceLabel: String {
        let source = sourceName.isEmpty ? "长桥新闻" : sourceName
        return "\(title) · \(source) · \(url)"
    }
}

struct IndustryReport: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let industry: String
    let executiveSummary: String
    let changes: [String]
    let portfolioImpact: String
    let counterEvidence: String
    let sources: [String]
    let periodStart: Date
    let periodEnd: Date
    let generatedAt: Date
    let modelName: String
    var isUnread: Bool
}

struct WorkspacePayload: Sendable {
    let portfolio: PortfolioSnapshot
    let strategy: InvestmentStrategy
    let advice: [AdviceItem]
    let schedules: [ResearchSchedule]
    let reports: [IndustryReport]
}

struct WorkspaceContent: Codable, Sendable {
    let strategy: InvestmentStrategy
    let advice: [AdviceItem]
    let schedules: [ResearchSchedule]
    let reports: [IndustryReport]
}

enum SyncState: Equatable, Sendable {
    case idle
    case syncing
    case success(Date)
    case failed(String)

    var label: String {
        switch self {
        case .idle: "等待同步"
        case .syncing: "正在同步"
        case .success: "同步完成"
        case .failed: "同步失败"
        }
    }
}

enum DataMode: String, CaseIterable, Codable, Sendable {
    case preview = "模拟数据"
    case live = "长桥账户"
}

struct LongbridgeConnectionDetails: Equatable, Sendable {
    let executablePath: String
    let cliVersion: String?
    let accountName: String?
    let accountNumberSuffix: String?
    let checkedAt: Date

    var accountLabel: String {
        if let accountName, !accountName.isEmpty {
            return accountName
        }
        if let accountNumberSuffix, !accountNumberSuffix.isEmpty {
            return "账户 ••••\(accountNumberSuffix)"
        }
        return "长桥账户"
    }
}

enum LongbridgeConnectionState: Equatable, Sendable {
    case unknown
    case checking
    case cliMissing
    case loginRequired(String)
    case authenticating(String)
    case connected(LongbridgeConnectionDetails)
    case failed(String)

    var label: String {
        switch self {
        case .unknown: "等待检测"
        case .checking: "正在检测"
        case .cliMissing: "需要安装组件"
        case .loginRequired: "等待登录"
        case .authenticating: "等待授权"
        case .connected: "已连接"
        case .failed: "连接异常"
        }
    }

    var detail: String {
        switch self {
        case .unknown:
            "尚未检测本机的长桥连接状态。"
        case .checking:
            "正在检查官方长桥组件和账户权限。"
        case .cliMissing:
            "需要先安装长桥官方组件，安装后即可在浏览器完成一次 OAuth 授权。"
        case .loginRequired:
            "官方组件已就绪，请登录并授予账户与行情的只读权限。"
        case .authenticating:
            "请在已打开的浏览器页面完成长桥授权，应用会自动继续。"
        case .connected(let details):
            "\(details.accountLabel)已通过官方 OAuth 连接；AI Invest 不提供下单能力。"
        case .failed(let message):
            message
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var executablePath: String? {
        switch self {
        case .loginRequired(let path), .authenticating(let path): path
        case .connected(let details): details.executablePath
        default: nil
        }
    }
}

enum GPTConnectionState: Equatable, Sendable {
    case notConfigured
    case configured
    case validating
    case ready
    case failed(String)

    var label: String {
        switch self {
        case .notConfigured: "未配置"
        case .configured: "已保存"
        case .validating: "正在验证"
        case .ready: "可用"
        case .failed: "连接异常"
        }
    }

    var detail: String {
        switch self {
        case .notConfigured: "未配置时使用本地模拟研报，不会调用 OpenAI API。"
        case .configured: "API Key 已保存在 macOS Keychain，可测试连接。"
        case .validating: "正在调用 Responses API 验证模型访问权限。"
        case .ready: "定时任务将使用真实 GPT 生成结构化研报。"
        case .failed(let message): message
        }
    }

    var isConfigured: Bool {
        switch self {
        case .configured, .validating, .ready, .failed: true
        case .notConfigured: false
        }
    }
}
