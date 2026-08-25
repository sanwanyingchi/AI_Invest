import Foundation

enum LearningTrack: String, CaseIterable, Identifiable, Codable, Sendable {
    case assetAllocation = "资产配置"
    case stockSelection = "基本面与选股"
    case industryResearch = "行业研究"
    case integration = "综合实践"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .assetAllocation: "chart.pie.fill"
        case .stockSelection: "building.2.crop.circle.fill"
        case .industryResearch: "square.stack.3d.up.fill"
        case .integration: "checklist.checked"
        }
    }

    var outcome: String {
        switch self {
        case .assetAllocation: "形成资产配置与再平衡规则"
        case .stockSelection: "形成可重复使用的选股评分卡"
        case .industryResearch: "形成统一的行业分析模板"
        case .integration: "完成个人投资手册 v1.0"
        }
    }
}

enum LessonSource: String, Codable, Sendable {
    case builtIn = "内置核心课程"
    case codex = "Codex 每日生成"
}

struct LearningQuizQuestion: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let prompt: String
    let options: [String]
    let correctIndex: Int
    let explanation: String
}

struct LearningUnit: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let week: Int
    let day: Int
    let track: LearningTrack
    let title: String
    let objective: String
    let summary: String
    let keyPoints: [String]
    let example: String
    let exercise: String
    let quiz: [LearningQuizQuestion]
    let reviewQuestions: [String]
    let suggestedCodexQuestions: [String]
    let source: LessonSource
    let generatedAt: Date?

    var dayInWeek: Int { ((day - 1) % 7) + 1 }
    var durationLabel: String { "约 20 分钟" }
}

struct LearningSourceReference: Identifiable, Hashable, Codable, Sendable {
    let title: String
    let publisher: String
    let url: String
    let note: String

    var id: String { url }
    var linkURL: URL? { URL(string: url) }
}

/// A learning aid distilled from public primary materials. These profiles are
/// lenses for improving the user's own process, never personas to imitate.
struct InvestorThinkingProfile: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let identity: String
    let oneLineMethod: String
    let principles: [String]
    let decisionProcess: [String]
    let usefulFor: [MethodologySection]
    let limitations: [String]
    let practiceQuestions: [String]
    let sources: [LearningSourceReference]
    let accentName: String
}

enum LessonProgressStatus: String, Codable, Sendable {
    case notStarted = "未开始"
    case inProgress = "学习中"
    case completed = "已完成"
}

struct LessonProgress: Hashable, Codable, Sendable {
    let unitID: String
    var status: LessonProgressStatus
    var quizScore: Double?
    var confidence: Int
    var completedAt: Date?
    var updatedAt: Date

    static func empty(for unitID: String) -> LessonProgress {
        LessonProgress(
            unitID: unitID,
            status: .notStarted,
            quizScore: nil,
            confidence: 0,
            completedAt: nil,
            updatedAt: .now
        )
    }
}

enum MethodologySection: String, CaseIterable, Identifiable, Codable, Sendable {
    case assetAllocation = "资产配置规则"
    case stockSelection = "选股评分卡"
    case industryResearch = "行业分析模板"
    case riskDiscipline = "风险与决策纪律"
    case decisionChecklist = "投资决策清单"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .assetAllocation: "chart.pie"
        case .stockSelection: "list.number"
        case .industryResearch: "building.columns"
        case .riskDiscipline: "shield.checkered"
        case .decisionChecklist: "checklist"
        }
    }

    var starter: String {
        switch self {
        case .assetAllocation:
            "目标与期限：\n目标比例：\n单一资产上限：\n再平衡触发条件："
        case .stockSelection:
            "能力圈：\n商业模式：\n财务质量：\n护城河：\n估值与安全边际：\n证伪条件："
        case .industryResearch:
            "价值链：\n发展阶段：\n供需与周期：\n竞争格局：\n核心指标：\n主要风险："
        case .riskDiscipline:
            "最大可接受回撤：\n集中度红线：\n不使用的工具：\n情绪化决策冷静期："
        case .decisionChecklist:
            "买入前：\n持有中：\n减仓或退出：\n复盘："
        }
    }
}

struct MethodologyNote: Identifiable, Hashable, Codable, Sendable {
    let section: MethodologySection
    var content: String
    var updatedAt: Date

    var id: String { section.rawValue }
}

struct LearningNote: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let unitID: String?
    var body: String
    let createdAt: Date
    var updatedAt: Date
}

struct LearningSettings: Hashable, Codable, Sendable {
    var courseStartDate: Date
    var dailyMinutes: Int
    var generationHour: Int
    var generationMinute: Int
    var workspacePath: String?
    var holdingsContextEnabled: Bool
    var updatedAt: Date

    static var `default`: LearningSettings {
        LearningSettings(
            courseStartDate: Calendar.current.startOfDay(for: .now),
            dailyMinutes: 20,
            generationHour: 8,
            generationMinute: 0,
            workspacePath: nil,
            holdingsContextEnabled: false,
            updatedAt: .now
        )
    }

    var generationTimeLabel: String {
        String(format: "%02d:%02d", generationHour, generationMinute)
    }
}

struct LearningState: Sendable {
    let units: [LearningUnit]
    let progress: [String: LessonProgress]
    let methodology: [MethodologyNote]
    let notes: [LearningNote]
    let settings: LearningSettings
}

enum LearningSyncState: Equatable, Sendable {
    case notConnected
    case ready(String)
    case syncing
    case succeeded(Int, Date)
    case failed(String)

    var label: String {
        switch self {
        case .notConnected: "尚未连接"
        case .ready: "已连接"
        case .syncing: "正在同步"
        case .succeeded(let count, _): "已同步 \(count) 节"
        case .failed: "同步失败"
        }
    }
}

struct QuizAttempt: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let unitID: String
    let score: Double
    let attemptedAt: Date
}
