import Foundation
import Security

enum OpenAIResearchError: LocalizedError, Sendable {
    case keychain(String)
    case invalidAPIKey
    case invalidResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .keychain(let message): "无法访问 macOS Keychain：\(message)"
        case .invalidAPIKey: "API Key 为空或格式不正确。"
        case .invalidResponse: "OpenAI 返回了无法识别的内容。"
        case .api(let message): "OpenAI API：\(message)"
        }
    }
}

protocol GPTCredentialStoring: Sendable {
    func save(apiKey: String) throws
    func loadAPIKey() throws -> String?
    func delete() throws
}

struct GPTKeychainStore: GPTCredentialStoring {
    private let service = "com.personal.AIInvest.openai"
    private let account = "research-api-key"

    func save(apiKey: String) throws {
        let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.hasPrefix("sk-"), normalized.count > 12 else {
            throw OpenAIResearchError.invalidAPIKey
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData: Data(normalized.utf8)] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw keychainError(updateStatus) }

        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData: Data(normalized.utf8)
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw keychainError(status) }
    }

    func loadAPIKey() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw keychainError(status)
        }
        return String(data: data, encoding: .utf8)
    }

    func delete() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(status)
        }
    }

    private func keychainError(_ status: OSStatus) -> OpenAIResearchError {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "状态码 \(status)"
        return .keychain(message)
    }
}

struct OpenAIResearchService: GPTResearchProviding {
    private struct ResponseEnvelope: Decodable {
        struct APIError: Decodable {
            let message: String
        }

        struct OutputItem: Decodable {
            struct WebSource: Decodable {
                let type: String?
                let url: String
                let title: String?
            }

            struct WebAction: Decodable {
                let type: String?
                let sources: [WebSource]?
            }

            struct Content: Decodable {
                let type: String
                let text: String?
                let refusal: String?
            }

            let type: String?
            let content: [Content]?
            let action: WebAction?
        }

        let status: String?
        let outputText: String?
        let output: [OutputItem]?
        let error: APIError?

        enum CodingKeys: String, CodingKey {
            case status
            case outputText = "output_text"
            case output
            case error
        }

        var text: String? {
            if let outputText, !outputText.isEmpty { return outputText }
            return output?
                .flatMap { $0.content ?? [] }
                .first { $0.type == "output_text" }?
                .text
        }

        var refusal: String? {
            output?
                .flatMap { $0.content ?? [] }
                .compactMap(\.refusal)
                .first
        }

        var webSources: [OutputItem.WebSource] {
            output?
                .filter { $0.type == "web_search_call" }
                .flatMap { $0.action?.sources ?? [] }
                ?? []
        }
    }

    private struct ReportDraft: Decodable {
        let title: String
        let executiveSummary: String
        let changes: [String]
        let portfolioImpact: String
        let counterEvidence: String
    }

    let apiKey: String
    let model: String
    private let endpoint: URL
    private let session: URLSession

    init(
        apiKey: String,
        model: String = "gpt-5.4-mini",
        endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
        self.session = session
    }

    func validateConnection() async throws {
        let payload: [String: Any] = [
            "model": model,
            "instructions": "Reply with the single word OK.",
            "input": "Connection test",
            "max_output_tokens": 64,
            "store": false
        ]
        _ = try await createResponse(payload: payload)
    }

    func generateIndustryReport(
        schedule: ResearchSchedule,
        portfolio: PortfolioSnapshot,
        previousReport: IndustryReport?,
        evidence: [ResearchEvidence]
    ) async throws -> IndustryReport {
        var payload: [String: Any] = [
            "model": model,
            "instructions": instructions,
            "input": makePrompt(
                schedule: schedule,
                portfolio: portfolio,
                previousReport: previousReport,
                evidence: evidence
            ),
            "max_output_tokens": 2_048,
            "store": false,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "ai_invest_industry_report",
                    "strict": true,
                    "schema": reportSchema
                ]
            ]
        ]

        let selectedInstitutions = schedule.selectedInstitutionSources
        let allowedDomains = selectedInstitutions.map(\.domain)
        if !allowedDomains.isEmpty {
            payload["tools"] = [[
                "type": "web_search",
                "filters": ["allowed_domains": allowedDomains],
                "search_context_size": "medium"
            ]]
            payload["tool_choice"] = "auto"
            payload["max_tool_calls"] = 6
            payload["include"] = ["web_search_call.action.sources"]
        }

        let response = try await createResponse(payload: payload)
        if let refusal = response.refusal {
            throw OpenAIResearchError.api(refusal)
        }
        guard let text = response.text, let data = text.data(using: .utf8) else {
            throw OpenAIResearchError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let draft: ReportDraft
        do {
            draft = try decoder.decode(ReportDraft.self, from: data)
        } catch {
            throw OpenAIResearchError.invalidResponse
        }

        let periodStart = previousReport?.periodEnd
            ?? Calendar.current.date(byAdding: .day, value: -7, to: .now)
            ?? .now
        var sources = ["AI Invest 本地持仓快照"]
        if previousReport != nil { sources.append("上一期行业研报") }
        sources.append(contentsOf: evidence.map(\.sourceLabel))
        sources.append(contentsOf: institutionSourceLabels(
            from: response.webSources,
            allowed: selectedInstitutions
        ))

        return IndustryReport(
            id: UUID().uuidString,
            title: draft.title,
            industry: schedule.industryScope,
            executiveSummary: draft.executiveSummary,
            changes: draft.changes,
            portfolioImpact: draft.portfolioImpact,
            counterEvidence: draft.counterEvidence,
            sources: sources,
            periodStart: periodStart,
            periodEnd: .now,
            generatedAt: .now,
            modelName: model,
            isUnread: true
        )
    }

    private var instructions: String {
        """
        你是个人稳健投资的研究助理。允许使用用户输入中的持仓快照、上一期研报、长桥新闻证据，以及本次 web_search 从白名单机构官方域名取得的公开材料。
        机构材料只能表述为“该机构公开材料的观点”，必须写明机构与发布日期；不得暗示获得了客户专属、付费、私有或未公开券商研报。不得把机构观点当作已验证事实。
        白名单以外的信息、缺少原始链接的二次转述，以及没有被输入或工具结果覆盖的实时新闻、公告、财务数据和估值，都必须明确写“证据不足”或“待核验”。
        输出是研究复盘，不是投资建议。不得给出买入、卖出、目标价、收益承诺或自动交易指令。
        重点说明组合暴露、需要验证的问题、反面证据和下一步研究清单，使用简洁中文。
        """
    }

    private func makePrompt(
        schedule: ResearchSchedule,
        portfolio: PortfolioSnapshot,
        previousReport: IndustryReport?,
        evidence: [ResearchEvidence]
    ) -> String {
        let relevant = portfolio.holdings.filter {
            schedule.industryScope == "全部持仓行业" || $0.sector == schedule.industryScope
        }
        let holdings = relevant.map { holding in
            let weight = portfolio.totalAssets == 0 ? 0 : holding.marketValue / portfolio.totalAssets * 100
            return "- \(holding.name)（\(holding.symbol)）｜行业：\(holding.sector)｜类型：\(holding.assetType.rawValue)｜组合权重：\(weight.formatted(.number.precision(.fractionLength(1))))%｜累计盈亏率：\(holding.totalProfitPercent.formatted(.number.precision(.fractionLength(1))))%"
        }.joined(separator: "\n")

        let previous = previousReport.map {
            "上一期摘要：\($0.executiveSummary)\n上一期反面证据：\($0.counterEvidence)"
        } ?? "没有上一期研报。"

        let evidenceText = evidence.isEmpty
            ? "- 未取得长桥新闻证据；所有外部变化必须标记为证据不足。"
            : evidence.map { item in
                "- \(item.title)｜来源：\(item.sourceName)｜时间：\(item.publishedAt)｜摘要：\(item.excerpt)｜链接：\(item.url)"
            }.joined(separator: "\n")

        let institutionText = schedule.selectedInstitutionSources.map {
            "- \($0.rawValue)｜类型：\($0.organizationKind)｜关注：\($0.focus)｜官方域名：\($0.domain)"
        }.joined(separator: "\n")

        return """
        任务：\(schedule.name)
        范围：\(schedule.industryScope)
        模板：\(schedule.template.rawValue)
        组合现金比例：\((portfolio.cashWeight * 100).formatted(.number.precision(.fractionLength(1))))%

        当前相关持仓：
        \(holdings.isEmpty ? "- 当前没有相关持仓。" : holdings)

        \(previous)

        长桥新闻证据：
        \(evidenceText)

        定向机构公开研究源：
        \(institutionText.isEmpty ? "- 本任务未选择机构公开研究源。" : institutionText)

        请先按当前行业与港股相关性，在所选官方域名检索最近 30 天的公开研究或市场观点；若最近 30 天没有相关材料，可扩大到最近 90 天并明确日期。每条采用的机构观点必须在“本期变化”中以“[机构公开观点｜机构名｜发布日期]”开头，并同时提供相反情景或局限。没有找到官方原文时写“未找到可验证的机构公开材料”，不要用二次转载补齐。

        请生成结构化行业复盘。没有覆盖到的财务、估值、公告或行业数据必须明确列出待核验事项。
        """
    }

    private func institutionSourceLabels(
        from sources: [ResponseEnvelope.OutputItem.WebSource],
        allowed: [InstitutionResearchSource]
    ) -> [String] {
        var seen = Set<String>()
        return sources.compactMap { source in
            guard let url = URL(string: source.url),
                  let host = url.host?.lowercased(),
                  let institution = allowed.first(where: {
                      host == $0.domain || host.hasSuffix(".\($0.domain)")
                  }),
                  seen.insert(source.url).inserted else { return nil }

            let title = source.title?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(100)
            let displayTitle = title.map(String.init).flatMap { $0.isEmpty ? nil : $0 }
                ?? "官方公开研究"
            return "\(displayTitle) · \(institution.rawValue) · \(source.url)"
        }
    }

    private var reportSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "executive_summary": ["type": "string"],
                "changes": [
                    "type": "array",
                    "items": ["type": "string"],
                    "minItems": 2,
                    "maxItems": 5
                ],
                "portfolio_impact": ["type": "string"],
                "counter_evidence": ["type": "string"]
            ],
            "required": [
                "title",
                "executive_summary",
                "changes",
                "portfolio_impact",
                "counter_evidence"
            ],
            "additionalProperties": false
        ]
    }

    private func createResponse(payload: [String: Any]) async throws -> ResponseEnvelope {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 150
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenAIResearchError.api(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenAIResearchError.invalidResponse
        }
        let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: data)
        guard (200..<300).contains(http.statusCode) else {
            throw OpenAIResearchError.api(
                envelope?.error?.message ?? "请求失败（HTTP \(http.statusCode)）。"
            )
        }
        guard let envelope else { throw OpenAIResearchError.invalidResponse }
        if let error = envelope.error { throw OpenAIResearchError.api(error.message) }
        return envelope
    }
}
