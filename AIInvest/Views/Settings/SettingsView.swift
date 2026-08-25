import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var monthlyBudget = 100.0
    @State private var allowBackgroundReports = true
    @State private var apiKey = ""
    @State private var model = "gpt-5.4-mini"

    var body: some View {
        TabView {
            Form {
                Section("数据连接") {
                    LabeledContent("长桥账户") {
                        StatusPill(
                            text: appModel.longbridgeConnectionState.label,
                            tint: longbridgeTint,
                            systemImage: longbridgeSystemImage
                        )
                    }
                    LabeledContent("当前模式", value: appModel.dataMode.rawValue)

                    Text(appModel.longbridgeConnectionState.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let message = appModel.longbridgeMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(message.contains("失败") ? AppTheme.negative : AppTheme.accent)
                    }

                    longbridgeActions

                    if case .connected(let details) = appModel.longbridgeConnectionState {
                        if let version = details.cliVersion {
                            LabeledContent("官方组件", value: version)
                        }
                        LabeledContent("最近检测", value: AppFormat.dateTime(details.checkedAt))
                    }

                    Text("只读取账户余额、股票持仓和行情；应用没有下单入口，也不会调用交易方法。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("组合") {
                    LabeledContent("基础币种", value: "港币 HKD")
                    LabeledContent("比较基准", value: "恒生指数（MVP 暂未计算超额收益）")
                }

                Section("本地数据") {
                    LabeledContent("数据库") {
                        StatusPill(
                            text: appModel.databaseStatus.label,
                            tint: databaseTint,
                            systemImage: "externaldrive.fill.badge.checkmark"
                        )
                    }

                    if let statistics = appModel.databaseStatistics {
                        LabeledContent("已保存持仓", value: "\(statistics.holdingCount)")
                        LabeledContent("价格记录", value: "\(statistics.pricePointCount)")
                        LabeledContent("交易记录", value: "\(statistics.tradeCount)")
                        LabeledContent("现金快照", value: "\(statistics.cashSnapshotCount)")
                        LabeledContent("学习课程", value: "\(statistics.learningUnitCount)")
                        LabeledContent("已完成课程", value: "\(statistics.completedLessonCount)")
                        LabeledContent("学习笔记", value: "\(statistics.learningNoteCount)")
                    }

                    if case .failed(let message) = appModel.databaseStatus {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(AppTheme.negative)
                            .textSelection(.enabled)
                    }

                    Text("现金、持仓、价格、交易账本和学习进度保存在本机 SQLite；只有你主动连接 Learning 文件夹或手动点击 Codex 生成时，应用才会发送相应的最小必要上下文。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding(20)
            .tabItem { Label("账户", systemImage: "person.crop.circle") }

            Form {
                Section("GPT") {
                    LabeledContent("研报服务") {
                        StatusPill(
                            text: appModel.gptConnectionState.label,
                            tint: gptTint,
                            systemImage: gptSystemImage
                        )
                    }

                    Text(appModel.gptConnectionState.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    SecureField(
                        appModel.gptConnectionState.isConfigured
                            ? "输入新 Key 可替换已保存的 Key"
                            : "OpenAI API Key（sk-…）",
                        text: $apiKey
                    )
                    .textContentType(.password)

                    TextField("模型", text: $model)

                    HStack {
                        Button("保存并测试") {
                            let key = apiKey
                            apiKey = ""
                            Task { await appModel.saveGPTConfiguration(apiKey: key, model: model) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            (!appModel.gptConnectionState.isConfigured
                                && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            || appModel.gptConnectionState == .validating
                        )

                        if appModel.gptConnectionState.isConfigured {
                            Button("测试连接") {
                                Task { await appModel.validateGPTConnection() }
                            }
                            .disabled(appModel.gptConnectionState == .validating)

                            Button("移除 Key", role: .destructive) {
                                appModel.removeGPTConfiguration()
                            }
                            .disabled(appModel.gptConnectionState == .validating)
                        }
                    }

                    if let message = appModel.gptMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(message.contains("失败") || message.contains("异常") ? AppTheme.negative : AppTheme.accent)
                    }

                    LabeledContent("月度预算（记录）") {
                        HStack {
                            Text("HKD")
                            TextField("预算", value: $monthlyBudget, format: .number)
                                .frame(width: 90)
                        }
                    }
                    Toggle("允许后台生成定时行业研报", isOn: $allowBackgroundReports)

                    Text("定时任务仅在 Mac 开机且 AI Invest 正在运行时触发；错过的任务会在下次启动时补跑一次。月度预算目前用于任务记录，不会代替 OpenAI 平台的用量限制。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Codex 策略与建议") {
                    LabeledContent("调用方式") {
                        StatusPill(
                            text: "本机 Codex CLI",
                            tint: AppTheme.info,
                            systemImage: "terminal"
                        )
                    }
                    Text("策略页和建议页提供独立的手动生成按钮。调用复用本机 Codex 登录，使用只读沙盒、临时会话、严格 JSON Schema 和实时 Web Search；不需要在 AI Invest 中保存另一份 API Key。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("发送内容包括持仓代码、名称、类型、行业、折算市值与权重、现金比例、现有策略论点和最近研报摘要；不会发送券商令牌、持仓成本、盈亏或交易流水。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("隐私") {
                    Text("长桥 OAuth 令牌由官方长桥组件加密保存，AI Invest 不读取令牌内容；OpenAI API Key 保存在 macOS Keychain。真实 GPT 研报只发送行业范围、必要的本地持仓摘要和上一期研报。Codex 仅在你确认手动生成后发送上方列出的最小上下文。两条链路均不发送券商令牌，也不具备交易能力。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding(20)
            .tabItem { Label("AI 与隐私", systemImage: "sparkles") }
        }
        .frame(width: 720, height: 620)
        .onAppear {
            model = appModel.gptModel
            monthlyBudget = appModel.monthlyAIBudget
            allowBackgroundReports = appModel.backgroundReportsEnabled
        }
        .onChange(of: monthlyBudget) { _, value in
            appModel.updateGPTPreferences(
                backgroundReportsEnabled: allowBackgroundReports,
                monthlyBudget: value
            )
        }
        .onChange(of: allowBackgroundReports) { _, value in
            appModel.updateGPTPreferences(
                backgroundReportsEnabled: value,
                monthlyBudget: monthlyBudget
            )
        }
    }

    @ViewBuilder
    private var longbridgeActions: some View {
        switch appModel.longbridgeConnectionState {
        case .unknown, .failed:
            Button("重新检测") {
                Task { await appModel.checkLongbridgeConnection() }
            }

        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在检查连接…")
                    .foregroundStyle(.secondary)
            }

        case .cliMissing:
            HStack {
                Link(
                    "查看官方安装说明",
                    destination: URL(string: "https://open.longbridge.com/docs/cli/install")!
                )
                Button("安装后重新检测") {
                    Task { await appModel.checkLongbridgeConnection() }
                }
            }

        case .loginRequired:
            HStack {
                Button("登录长桥") {
                    Task { await appModel.authenticateLongbridge() }
                }
                .buttonStyle(.borderedProminent)
                Button("重新检测") {
                    Task { await appModel.checkLongbridgeConnection() }
                }
            }

        case .authenticating:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("等待浏览器授权…")
                    .foregroundStyle(.secondary)
            }

        case .connected:
            HStack {
                if appModel.dataMode == .live {
                    Button("切换到模拟数据") {
                        Task { await appModel.usePreviewData() }
                    }
                } else {
                    Button("使用长桥真实数据") {
                        Task { await appModel.useLiveData() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("测试连接") {
                    Task { await appModel.checkLongbridgeConnection() }
                }
            }
        }
    }

    private var databaseTint: Color {
        switch appModel.databaseStatus {
        case .ready: AppTheme.positive
        case .failed: AppTheme.negative
        }
    }

    private var longbridgeTint: Color {
        switch appModel.longbridgeConnectionState {
        case .connected: AppTheme.positive
        case .checking, .authenticating: AppTheme.info
        case .failed: AppTheme.negative
        case .unknown, .cliMissing, .loginRequired: AppTheme.warning
        }
    }

    private var longbridgeSystemImage: String {
        switch appModel.longbridgeConnectionState {
        case .connected: "checkmark.circle.fill"
        case .checking, .authenticating: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.triangle.fill"
        case .cliMissing: "square.and.arrow.down"
        case .unknown, .loginRequired: "link.badge.plus"
        }
    }

    private var gptTint: Color {
        switch appModel.gptConnectionState {
        case .ready: AppTheme.positive
        case .configured, .validating: AppTheme.info
        case .failed: AppTheme.negative
        case .notConfigured: AppTheme.warning
        }
    }

    private var gptSystemImage: String {
        switch appModel.gptConnectionState {
        case .ready: "checkmark.circle.fill"
        case .configured: "key.fill"
        case .validating: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.triangle.fill"
        case .notConfigured: "key.slash"
        }
    }
}
