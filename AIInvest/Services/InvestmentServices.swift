import Foundation

enum ServiceError: LocalizedError {
    case notConfigured(String)
    case noEnabledSchedule

    var errorDescription: String? {
        switch self {
        case .notConfigured(let service): "\(service) 尚未配置"
        case .noEnabledSchedule: "没有可运行的行业研报任务"
        }
    }
}

protocol LongbridgeProviding: Sendable {
    func loadPortfolio() async throws -> PortfolioSnapshot
}

protocol LongbridgeConnecting: LongbridgeProviding {
    func connectionStatus() async -> LongbridgeConnectionState
    func authenticate() async throws
    func loadResearchEvidence(industry: String, holdings: [Holding]) async throws -> [ResearchEvidence]
}

protocol GPTResearchProviding: Sendable {
    func generateIndustryReport(
        schedule: ResearchSchedule,
        portfolio: PortfolioSnapshot,
        previousReport: IndustryReport?,
        evidence: [ResearchEvidence]
    ) async throws -> IndustryReport
}

struct MockLongbridgeService: LongbridgeProviding {
    func loadPortfolio() async throws -> PortfolioSnapshot {
        try await Task.sleep(for: .milliseconds(700))
        return PreviewData.workspace(updatedAt: .now).portfolio
    }
}

struct MockGPTResearchService: GPTResearchProviding {
    func generateIndustryReport(
        schedule: ResearchSchedule,
        portfolio: PortfolioSnapshot,
        previousReport: IndustryReport?,
        evidence: [ResearchEvidence]
    ) async throws -> IndustryReport {
        try await Task.sleep(for: .seconds(1.1))

        let impact = portfolio.holdings
            .filter { schedule.industryScope == "全部持仓行业" || $0.sector == schedule.industryScope }
            .sorted { $0.marketValue > $1.marketValue }
            .prefix(2)
            .map(\.name)
            .joined(separator: "、")

        let longbridgeSources = evidence.map(\.sourceLabel)
        let publicPortals = schedule.selectedInstitutionSources.map {
            "公开研究入口（模拟模式未检索最新内容） · \($0.rawValue) · \($0.portalURL.absoluteString)"
        }

        return IndustryReport(
            id: UUID().uuidString,
            title: "\(schedule.industryScope)｜本地模拟研究样例",
            industry: schedule.industryScope,
            executiveSummary: "当前处于本地模拟模式，没有检索实时市场、公司公告或机构网页。本报告只用于验证任务流程和版式，不代表最新行业判断。",
            changes: [
                "模拟模式未接入实时行业指数，无法判断本期相对表现。",
                "模拟模式没有调用机构官方网页检索，机构最新观点待核验。",
                previousReport == nil ? "这是该任务的首次运行，后续将提供环比差异。" : "与上一期相比，没有可验证的外部增量证据。"
            ],
            portfolioImpact: impact.isEmpty ? "当前组合没有直接相关持仓。" : "组合中主要相关持仓为\(impact)，当前证据不足以触发仓位建议。",
            counterEvidence: "这是模拟内容。形成任何判断前，需要核对原始公告、财务数据和带日期的公开研究原文。",
            sources: ["本地模拟研究数据"] + longbridgeSources + publicPortals,
            periodStart: Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now,
            periodEnd: .now,
            generatedAt: .now,
            modelName: schedule.modelName,
            isUnread: true
        )
    }
}

actor ResearchScheduler {
    func dueSchedules(in schedules: [ResearchSchedule], at date: Date = .now) -> [ResearchSchedule] {
        schedules.filter { $0.isEnabled && $0.nextRunAt <= date }
    }

    func nextRun(after date: Date, template: ReportTemplate) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        switch template {
        case .closeBrief:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        }
    }
}
