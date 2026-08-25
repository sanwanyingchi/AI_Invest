import AppKit
import Foundation

enum LearningWorkspaceError: LocalizedError {
    case notConnected
    case invalidFolder
    case unreadableLesson(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "请先连接项目中的 Learning 文件夹。"
        case .invalidFolder: "所选文件夹不可用。"
        case .unreadableLesson(let file): "无法读取 Codex 课程文件：\(file)"
        }
    }
}

struct LearningWorkspaceImport: Sendable {
    let units: [LearningUnit]
    let ignoredFiles: [String]
}

@MainActor
final class LearningWorkspaceService {
    private let bookmarkKey = "ai-invest.learning-workspace-bookmark"

    func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择 AI Invest 的 Learning 文件夹"
        panel.message = "Codex 将在这个文件夹生成每日课程；应用只读取学习内容并写入你的进度与提问上下文。"
        panel.prompt = "连接文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    func configure(url: URL) throws {
        guard url.hasDirectoryPath else { throw LearningWorkspaceError.invalidFolder }
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
    }

    func configuredURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale { try? configure(url: url) }
        return url
    }

    func importLessons() throws -> LearningWorkspaceImport {
        try withWorkspaceAccess { root in
            let lessonsURL = root.appendingPathComponent("lessons", isDirectory: true)
            guard FileManager.default.fileExists(atPath: lessonsURL.path) else {
                return LearningWorkspaceImport(units: [], ignoredFiles: [])
            }

            let files = try FileManager.default.contentsOfDirectory(
                at: lessonsURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var units: [LearningUnit] = []
            var ignored: [String] = []

            for file in files {
                do {
                    let data = try Data(contentsOf: file)
                    let unit = try decoder.decode(LearningUnit.self, from: data)
                    guard (1...28).contains(unit.day), (1...4).contains(unit.week) else {
                        ignored.append(file.lastPathComponent)
                        continue
                    }
                    units.append(unit)
                } catch {
                    ignored.append(file.lastPathComponent)
                }
            }

            return LearningWorkspaceImport(units: units, ignoredFiles: ignored)
        }
    }

    func exportState(
        progress: [String: LessonProgress],
        methodology: [MethodologyNote],
        holdings: [Holding],
        includeHoldings: Bool
    ) throws {
        try withWorkspaceAccess { root in
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("methodology", isDirectory: true),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("questions", isDirectory: true),
                withIntermediateDirectories: true
            )

            let progressFile = LearningProgressFile(
                updatedAt: .now,
                completedUnitIDs: progress.values
                    .filter { $0.status == .completed }
                    .map(\.unitID)
                    .sorted(),
                quizScores: progress.reduce(into: [:]) { result, item in
                    if let score = item.value.quizScore { result[item.key] = score }
                },
                confidence: progress.reduce(into: [:]) { result, item in
                    if item.value.confidence > 0 { result[item.key] = item.value.confidence }
                }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(progressFile).write(
                to: root.appendingPathComponent("progress.json"),
                options: .atomic
            )

            for note in methodology {
                let body = """
                # \(note.section.rawValue)

                更新时间：\(note.updatedAt.ISO8601Format())

                \(note.content)
                """
                let fileName = methodologyFileName(for: note.section)
                try Data(body.utf8).write(
                    to: root.appendingPathComponent("methodology/\(fileName)"),
                    options: .atomic
                )
            }

            let holdingsContext: String
            if includeHoldings {
                let lines = holdings.map {
                    "- \($0.symbol)｜\($0.name)｜\($0.assetType.rawValue)｜\($0.sector)"
                }
                holdingsContext = """
                # 可用于教学案例的最小持仓上下文

                仅包含代码、名称、资产类型和行业。不要推断或索取数量、成本、总资产或盈亏。

                \(lines.joined(separator: "\n"))
                """
            } else {
                holdingsContext = """
                # 持仓上下文未授权

                用户尚未允许将持仓代码或行业用于学习案例。请使用公开的港股、基金或虚构案例。
                """
            }
            try Data(holdingsContext.utf8).write(
                to: root.appendingPathComponent("holdings-context.md"),
                options: .atomic
            )
        }
    }

    @discardableResult
    func prepareQuestionContext(
        unit: LearningUnit,
        question: String,
        progress: LessonProgress?,
        methodology: [MethodologyNote]
    ) throws -> String {
        let prompt = "请使用 $investment-learning-coach，并读取 Learning/questions/current-context.md，回答我关于第\(unit.day)天课程《\(unit.title)》的问题：\(question)"

        try withWorkspaceAccess { root in
            let questionsURL = root.appendingPathComponent("questions", isDirectory: true)
            try FileManager.default.createDirectory(at: questionsURL, withIntermediateDirectories: true)
            let methodologySummary = methodology.map {
                "## \($0.section.rawValue)\n\($0.content)"
            }.joined(separator: "\n\n")
            let context = """
            # 当前学习提问上下文

            - 课程 ID：\(unit.id)
            - 第 \(unit.day) 天 / 第 \(unit.week) 周
            - 主题：\(unit.title)
            - 学习目标：\(unit.objective)
            - 当前测验分数：\(progress?.quizScore.map { "\(Int($0))" } ?? "尚未作答")

            ## 我的问题

            \(question)

            ## 本课核心内容

            \(unit.keyPoints.map { "- \($0)" }.joined(separator: "\n"))

            ## 当前个人方法论草稿

            \(methodologySummary)

            ## 回答要求

            请先诊断我缺少的是概念、证据还是应用能力，再用一个简洁案例解释；区分事实、观点和推断，不给出个性化买卖指令。
            """
            try Data(context.utf8).write(
                to: questionsURL.appendingPathComponent("current-context.md"),
                options: .atomic
            )
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        return prompt
    }

    @discardableResult
    func prepareQuestionContext(
        investor profile: InvestorThinkingProfile,
        question: String,
        methodology: [MethodologyNote]
    ) throws -> String {
        let prompt = "请使用 $investment-learning-coach，并读取 Learning/questions/current-context.md，回答我关于\(profile.name)投资方法的问题：\(question)"

        try withWorkspaceAccess { root in
            let questionsURL = root.appendingPathComponent("questions", isDirectory: true)
            try FileManager.default.createDirectory(at: questionsURL, withIntermediateDirectories: true)
            let methodologySummary = methodology.map {
                "## \($0.section.rawValue)\n\($0.content)"
            }.joined(separator: "\n\n")
            let sources = profile.sources.map {
                "- \($0.title)｜\($0.publisher)｜\($0.url)｜\($0.note)"
            }.joined(separator: "\n")
            let context = """
            # 当前投资人方法提问上下文

            - 投资人：\(profile.name)
            - 方法定位：\(profile.identity)
            - 一句话摘要：\(profile.oneLineMethod)

            ## 我的问题

            \(question)

            ## 方法原则

            \(profile.principles.map { "- \($0)" }.joined(separator: "\n"))

            ## 可执行流程

            \(profile.decisionProcess.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))

            ## 不能直接照搬

            \(profile.limitations.map { "- \($0)" }.joined(separator: "\n"))

            ## 公开原始材料

            \(sources)

            ## 当前个人方法论草稿

            \(methodologySummary)

            ## 回答要求

            将公开材料中的事实、投资人的观点和你的推断分开；说明完整语境和反方证据。帮助我把可迁移原则转化为自己的检查项，不模仿个股、仓位、买卖时点或收益目标。
            """
            try Data(context.utf8).write(
                to: questionsURL.appendingPathComponent("current-context.md"),
                options: .atomic
            )
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        return prompt
    }

    private func withWorkspaceAccess<T>(_ work: (URL) throws -> T) throws -> T {
        guard let root = configuredURL() else { throw LearningWorkspaceError.notConnected }
        let didStart = root.startAccessingSecurityScopedResource()
        defer {
            if didStart { root.stopAccessingSecurityScopedResource() }
        }
        return try work(root)
    }

    private func methodologyFileName(for section: MethodologySection) -> String {
        switch section {
        case .assetAllocation: "asset-allocation.md"
        case .stockSelection: "stock-selection.md"
        case .industryResearch: "industry-research.md"
        case .riskDiscipline: "risk-discipline.md"
        case .decisionChecklist: "decision-checklist.md"
        }
    }
}

private struct LearningProgressFile: Codable {
    let updatedAt: Date
    let completedUnitIDs: [String]
    let quizScores: [String: Double]
    let confidence: [String: Int]
}
