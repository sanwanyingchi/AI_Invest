import Foundation

enum LongbridgeServiceError: LocalizedError, Sendable {
    case cliNotInstalled
    case authenticationRequired
    case commandTimedOut
    case commandFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .cliNotInstalled:
            "没有找到长桥官方组件，请先在设置中完成安装。"
        case .authenticationRequired:
            "长桥登录已失效，请在设置中重新授权。"
        case .commandTimedOut:
            "长桥官方组件响应超时，请检查网络后重试。"
        case .commandFailed(let message):
            message
        case .invalidResponse(let detail):
            "无法读取长桥返回的数据：\(detail)"
        }
    }
}

struct LongbridgeCLIService: LongbridgeConnecting {
    private let client: LongbridgeCLIClient

    init(client: LongbridgeCLIClient = LongbridgeCLIClient()) {
        self.client = client
    }

    func connectionStatus() async -> LongbridgeConnectionState {
        await client.connectionStatus()
    }

    func authenticate() async throws {
        try await client.authenticate()
    }

    func loadPortfolio() async throws -> PortfolioSnapshot {
        try await client.loadPortfolio()
    }

    func loadResearchEvidence(industry: String, holdings: [Holding]) async throws -> [ResearchEvidence] {
        try await client.loadResearchEvidence(industry: industry, holdings: holdings)
    }
}

actor LongbridgeCLIClient {
    private let commandTimeout: Duration

    init(commandTimeout: Duration = .seconds(45)) {
        self.commandTimeout = commandTimeout
    }

    private struct CommandOutput {
        let status: Int32
        let stdout: String
        let stderr: String

        var failureMessage: String {
            let error = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !error.isEmpty { return error }
            let output = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return output.isEmpty ? "长桥组件运行失败（状态码 \(status)）。" : output
        }
    }

    private struct AuthStatusResponse: Decodable {
        struct Token: Decodable {
            let status: String
            let path: String?
        }

        struct Account: Decodable {
            let accountNo: String?
            let name: String?

            enum CodingKeys: String, CodingKey {
                case accountNo = "account_no"
                case name
            }
        }

        let token: Token
        let account: Account?
    }

    private struct CheckResponse: Decodable {
        struct Session: Decodable {
            let token: String?
        }

        struct Connectivity: Decodable {
            struct Endpoint: Decodable {
                let ok: Bool?
            }

            let global: Endpoint?
            let cn: Endpoint?
        }

        let session: Session?
        let connectivity: Connectivity?
    }

    private struct PortfolioResponse: Decodable {
        struct Overview: Decodable {
            let totalCash: FlexibleDouble
            let currency: String

            enum CodingKeys: String, CodingKey {
                case totalCash = "total_cash"
                case currency
            }
        }

        struct Position: Decodable {
            let symbol: String
            let name: String
            let currency: String
            let quantity: FlexibleDouble
            let availableQuantity: FlexibleDouble
            let costPrice: FlexibleDouble?
            let marketValue: FlexibleDouble
            let marketValueUSD: FlexibleDouble
            let marketPrice: FlexibleDouble
            let previousClose: FlexibleDouble?

            enum CodingKeys: String, CodingKey {
                case symbol
                case name
                case currency
                case quantity
                case availableQuantity = "available_quantity"
                case costPrice = "cost_price"
                case marketValue = "market_value"
                case marketValueUSD = "market_value_usd"
                case marketPrice = "market_price"
                case previousClose = "prev_close"
            }
        }

        let overview: Overview
        let holdings: [Position]
    }

    private struct NewsSearchItem: Decodable {
        let id: FlexibleString
        let title: String?
        let sourceName: String?
        let time: String?
        let excerpt: String?
        let url: String?

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case sourceName = "source_name"
            case time
            case excerpt
            case url
        }
    }

    private struct FlexibleString: Decodable {
        let value: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                self.value = value
            } else if let value = try? container.decode(Int64.self) {
                self.value = String(value)
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "期望字符串或整数"
                )
            }
        }
    }

    private struct FlexibleDouble: Decodable {
        let value: Double

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Double.self) {
                self.value = value
                return
            }
            if let string = try? container.decode(String.self), let value = Double(string) {
                self.value = value
                return
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "期望数字或数字字符串"
            )
        }
    }

    func connectionStatus() async -> LongbridgeConnectionState {
        guard let executable = locateExecutable() else {
            return .cliMissing
        }

        do {
            let authOutput = try await run(
                executable: executable,
                arguments: ["auth", "status", "--format", "json"]
            )
            guard authOutput.status == 0 else {
                return .failed(cleanFailure(authOutput.failureMessage))
            }

            let auth: AuthStatusResponse = try decodeJSON(authOutput.stdout)
            guard isUsableTokenStatus(auth.token.status) else {
                return .loginRequired(executable.path)
            }

            let checkOutput = try await run(
                executable: executable,
                arguments: ["check", "--format", "json"]
            )
            guard checkOutput.status == 0 else {
                return .failed(cleanFailure(checkOutput.failureMessage))
            }

            let check: CheckResponse = try decodeJSON(checkOutput.stdout)
            guard check.session?.token == "valid" else {
                return .loginRequired(executable.path)
            }

            let canReachAPI = check.connectivity?.global?.ok == true
                || check.connectivity?.cn?.ok == true
            guard canReachAPI else {
                return .failed("长桥授权仍有效，但当前无法连接长桥服务，请检查网络后重试。")
            }

            let versionOutput = try? await run(executable: executable, arguments: ["--version"])
            let version = versionOutput?.stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty

            return .connected(
                LongbridgeConnectionDetails(
                    executablePath: executable.path,
                    cliVersion: version,
                    accountName: auth.account?.name?.nilIfEmpty,
                    accountNumberSuffix: auth.account?.accountNo.map { String($0.suffix(4)) },
                    checkedAt: .now
                )
            )
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func authenticate() async throws {
        guard let executable = locateExecutable() else {
            throw LongbridgeServiceError.cliNotInstalled
        }

        let output = try await run(
            executable: executable,
            arguments: ["auth", "login", "--client-name", "AI Invest macOS"]
        )
        guard output.status == 0 else {
            throw LongbridgeServiceError.commandFailed(cleanFailure(output.failureMessage))
        }
    }

    func loadPortfolio() async throws -> PortfolioSnapshot {
        guard let executable = locateExecutable() else {
            throw LongbridgeServiceError.cliNotInstalled
        }

        let authOutput = try await run(
            executable: executable,
            arguments: ["auth", "status", "--format", "json"]
        )
        guard authOutput.status == 0 else {
            throw LongbridgeServiceError.commandFailed(cleanFailure(authOutput.failureMessage))
        }
        let auth: AuthStatusResponse = try decodeJSON(authOutput.stdout)
        guard isUsableTokenStatus(auth.token.status) else {
            throw LongbridgeServiceError.authenticationRequired
        }

        let output = try await run(
            executable: executable,
            arguments: ["portfolio", "--format", "json"]
        )
        guard output.status == 0 else {
            throw LongbridgeServiceError.commandFailed(cleanFailure(output.failureMessage))
        }

        let response: PortfolioResponse = try decodeJSON(output.stdout)
        return makePortfolio(from: response)
    }

    func loadResearchEvidence(industry: String, holdings: [Holding]) async throws -> [ResearchEvidence] {
        guard let executable = locateExecutable() else {
            throw LongbridgeServiceError.cliNotInstalled
        }

        let relevant = holdings
            .filter { industry == "全部持仓行业" || $0.sector == industry }
            .sorted { $0.marketValue > $1.marketValue }
            .prefix(3)

        var collected: [ResearchEvidence] = []
        var lastError: Error?
        for holding in relevant {
            do {
                let output = try await run(
                    executable: executable,
                    arguments: ["news", "search", holding.name, "--count", "3", "--format", "json"]
                )
                guard output.status == 0 else {
                    throw LongbridgeServiceError.commandFailed(cleanFailure(output.failureMessage))
                }
                let items: [NewsSearchItem] = try decodeJSON(output.stdout)
                collected.append(contentsOf: items.prefix(2).map { item in
                    ResearchEvidence(
                        id: item.id.value,
                        title: item.title?.nilIfEmpty ?? "未命名新闻",
                        excerpt: item.excerpt ?? "",
                        sourceName: item.sourceName ?? "长桥新闻",
                        publishedAt: item.time ?? "",
                        url: item.url ?? "https://longbridge.com/news/\(item.id.value).md"
                    )
                })
            } catch {
                lastError = error
            }
        }

        let unique = Dictionary(grouping: collected, by: \.url)
            .compactMap { $0.value.first }
            .sorted { $0.publishedAt > $1.publishedAt }
        if unique.isEmpty, let lastError { throw lastError }
        return Array(unique.prefix(6))
    }

    private func makePortfolio(from response: PortfolioResponse) -> PortfolioSnapshot {
        let usdToHKD = inferredUSDToHKD(from: response.holdings)

        let holdings = response.holdings.map { position in
            let nativeValue = position.marketValue.value
            let nativeToUSD: Double
            if nativeValue != 0, position.marketValueUSD.value != 0 {
                nativeToUSD = position.marketValueUSD.value / nativeValue
            } else {
                nativeToUSD = fallbackNativeToUSD(for: position.currency)
            }
            let exchangeRateToHKD = nativeToUSD * usdToHKD
            let previousClose = position.previousClose?.value ?? 0
            let dailyChange = previousClose == 0
                ? 0
                : (position.marketPrice.value - previousClose) / previousClose * 100

            return Holding(
                symbol: position.symbol,
                name: position.name.isEmpty ? position.symbol : position.name,
                assetType: inferAssetType(symbol: position.symbol, name: position.name),
                sector: inferSector(symbol: position.symbol, name: position.name),
                currency: position.currency,
                shares: position.quantity.value,
                availableShares: position.availableQuantity.value,
                averageCost: position.costPrice?.value ?? 0,
                lastPrice: position.marketPrice.value,
                dailyChangePercent: dailyChange,
                exchangeRateToBase: exchangeRateToHKD,
                source: .longbridge,
                note: "",
                updatedAt: .now
            )
        }

        let cashInHKD: Double
        switch response.overview.currency.uppercased() {
        case "HKD": cashInHKD = response.overview.totalCash.value
        case "USD": cashInHKD = response.overview.totalCash.value * usdToHKD
        default:
            cashInHKD = response.overview.totalCash.value
                * fallbackNativeToUSD(for: response.overview.currency)
                * usdToHKD
        }

        return PortfolioSnapshot(
            holdings: holdings,
            cash: cashInHKD,
            currency: "HKD",
            updatedAt: .now
        )
    }

    private func inferredUSDToHKD(from positions: [PortfolioResponse.Position]) -> Double {
        for position in positions where position.currency.uppercased() == "HKD" {
            let native = position.marketValue.value
            let usd = position.marketValueUSD.value
            if native > 0, usd > 0 {
                return native / usd
            }
        }
        return 7.80
    }

    private func fallbackNativeToUSD(for currency: String) -> Double {
        switch currency.uppercased() {
        case "HKD": 1 / 7.80
        case "USD": 1
        case "CNY", "CNH": 0.14
        case "SGD": 0.78
        default: 1
        }
    }

    private func inferAssetType(symbol: String, name: String) -> AssetType {
        let normalized = "\(symbol) \(name)".uppercased()
        if normalized.contains("ETF") || normalized.contains("基金") || normalized.contains("TRACKER") {
            return .etf
        }
        return .stock
    }

    private func inferSector(symbol: String, name: String) -> String {
        let knownSectors = [
            "700.HK": "资讯科技",
            "9988.HK": "资讯科技",
            "1299.HK": "金融",
            "5.HK": "金融",
            "388.HK": "金融",
            "2800.HK": "ETF"
        ]
        if let sector = knownSectors[symbol.uppercased()] { return sector }
        return inferAssetType(symbol: symbol, name: name) == .etf ? "ETF" : "待分类"
    }

    private func isUsableTokenStatus(_ status: String) -> Bool {
        ["present", "valid", "refresh_pending"].contains(status)
    }

    private func locateExecutable() -> URL? {
        var candidates: [String] = []
        if let customPath = UserDefaults.standard.string(forKey: "longbridge.executablePath") {
            candidates.append(customPath)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/longbridge",
            "/usr/local/bin/longbridge",
            "\(home)/.local/bin/longbridge",
            "\(home)/bin/longbridge"
        ])

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/longbridge" })
        }

        for path in candidates {
            let standardized = URL(fileURLWithPath: path).standardizedFileURL
            if FileManager.default.isExecutableFile(atPath: standardized.path) {
                UserDefaults.standard.set(standardized.path, forKey: "longbridge.executablePath")
                return standardized
            }
        }
        return nil
    }

    private func run(executable: URL, arguments: [String]) async throws -> CommandOutput {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw LongbridgeServiceError.commandFailed(
                "无法启动长桥官方组件：\(error.localizedDescription)"
            )
        }

        let stdoutTask = Task.detached {
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }
        let stderrTask = Task.detached {
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }
        let exitTask = Task.detached {
            process.waitUntilExit()
            return process.terminationStatus
        }
        let timeout = commandTimeout
        let timeoutTask = Task.detached {
            do {
                try await Task.sleep(for: timeout)
                guard process.isRunning else { return false }
                process.terminate()
                return true
            } catch {
                return false
            }
        }

        let status = await withTaskCancellationHandler {
            await exitTask.value
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        timeoutTask.cancel()
        let didTimeOut = await timeoutTask.value
        let stdoutData = await stdoutTask.value
        let stderrData = await stderrTask.value

        if didTimeOut { throw LongbridgeServiceError.commandTimedOut }
        try Task.checkCancellation()

        return CommandOutput(
            status: status,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    private func decodeJSON<T: Decodable>(_ text: String) throws -> T {
        let objectStart = text.firstIndex(of: "{")
        let arrayStart = text.firstIndex(of: "[")
        guard let start = [objectStart, arrayStart].compactMap({ $0 }).min() else {
            throw LongbridgeServiceError.invalidResponse("返回内容不是 JSON。")
        }
        let end = text[start] == "[" ? text.lastIndex(of: "]") : text.lastIndex(of: "}")
        guard let end, start <= end,
              let data = String(text[start...end]).data(using: .utf8) else {
            throw LongbridgeServiceError.invalidResponse("返回的 JSON 不完整。")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LongbridgeServiceError.invalidResponse(error.localizedDescription)
        }
    }

    private func cleanFailure(_ message: String) -> String {
        let lines = message
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Error:") }
        return lines.last ?? "长桥连接失败，请稍后重试。"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
