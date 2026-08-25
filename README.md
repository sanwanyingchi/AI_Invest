# AI Invest

AI Invest 是一款个人自用的原生 macOS SwiftUI 投资工作台，面向稳健的港股资产管理。它把持仓、策略、建议、行业研报和 4 周投资学习放在一个本地优先的应用中；不提供下单、改单或撤单能力。

## MVP 已实现

- 五个左侧菜单：持仓、策略、建议、行业研报、学习。
- 长桥真实/模拟双模式：使用长桥官方终端完成 OAuth，读取账户组合、持仓、价格、现金和少量持仓相关新闻证据。
- 手动持仓：基金、ETF、加密货币、债券、现金及其他资产；支持原币估值、HKD 折算、编辑和删除。
- 本地交易账本：记录买卖、费用和现金影响；只写本机，不向券商发送订单。
- 行业分类：手动资产可直接录入行业；长桥持仓可添加本地行业标签，刷新后保留。
- 策略与建议：策略规则实时检查、论点复核、建议状态流转和周度 Markdown 导出；可手动调用本机 Codex CLI，结合实时公开信息、金融理论和现有研报动态生成。
- 定时行业研报：按行业创建、启停、立即运行和删除任务；支持真实 OpenAI Responses API、结构化输出、长桥新闻来源链接及失败降级。
- 机构公开研究：定向检索 Morgan Stanley、Bridgewater、Goldman Sachs 和 J.P. Morgan 的官方域名；按任务选择来源、保存实际采用的原文链接，并明确区分公开观点与付费研报。
- 4 周 / 28 天投资学习：资产配置、基本面选股、行业研究和综合实践；包含测验、复习、笔记与《个人投资手册 v1.0》。
- 投资人方法：比较学习巴菲特、芒格和段永平的公开思想，包含可执行流程、适用边界、反向练习和一手材料；不延长 28 天课程，也不复制个股或仓位。
- Codex 学习上下文：`Learning/` 保存课程、进度、方法论和当前提问；每日 08:00 的 Codex 任务会逐日生成课程。
- SQLite v3：持仓、价格、现金快照、交易、策略、建议、研报、任务和学习状态均在本机持久化。
- macOS Keychain：OpenAI API Key 不写入数据库、配置文件或日志。

## 直接运行

要求：macOS 14 或更高版本、Apple Silicon Mac、Xcode 15.4 或更高版本。

1. 用 Xcode 打开 `AIInvest.xcodeproj`。
2. 选择 `AIInvest` Scheme 和 `My Mac`。
3. 点击 Run。

首次启动默认使用“模拟数据”，因此没有任何外部账号也能完整浏览和试用。也可以在终端运行 `./scripts/verify.sh`；脚本会先执行 11 组临时数据库与领域回归测试，再验证 Debug 与 Release 构建，不会接触正式持仓数据库。

## 连接长桥真实数据

1. 按[长桥官方安装说明](https://open.longbridge.com/docs/cli/install)安装终端组件；Homebrew 可使用 `brew install --cask longbridge/tap/longbridge-terminal`。
2. 打开 AI Invest → 设置 → 账户，点击“重新检测”。
3. 点击“登录长桥”，在浏览器完成官方 OAuth 授权。
4. 连接测试通过后，点击“使用长桥真实数据”。

应用只调用官方终端的只读组合和新闻搜索能力。OAuth 令牌由长桥官方组件管理，AI Invest 不读取令牌内容，也没有任何交易方法或交易界面。未识别行业的长桥持仓可在持仓表最右侧菜单中选择“设置行业”。

## 开启真实 GPT 研报

1. 打开 AI Invest → 设置 → AI 与隐私。
2. 输入自己的 OpenAI API Key，模型默认使用 `gpt-5.4-mini`。
3. 点击“保存并测试”。
4. 在“行业研报”中新建任务并先执行一次。

API Key 保存于 macOS Keychain。调用使用 Responses API、`store: false`、严格 JSON Schema 和官方 Web Search。发送内容仅包含任务范围、必要的持仓摘要、上一期研报、本次取得的长桥新闻证据和所选机构官方域名；不会发送长桥令牌。Web Search 只允许访问 `morganstanley.com`、`bridgewater.com`、`goldmansachs.com` 和 `jpmorgan.com`，响应中实际使用的公开原文链接会随研报保存。未配置 Key 时任务使用明确标注的本地模拟研报，不会伪装成已取得最新机构观点。

“机构观点”页提供四个官方公开研究入口。Morgan Stanley、高盛和摩根大通属于投行研究来源；桥水是资产管理机构。应用不会绕过登录、订阅、付费墙或版权限制，也不声称获得客户专属券商研报。

定时任务每 15 分钟检查一次，仅在 Mac 开机且 AI Invest 正在运行时触发；错过的任务会在下次启动时补跑一次。设置中的月度预算是本地记录值，不会代替 OpenAI 平台用量限制。

## 使用 Codex 生成策略与建议

1. 在终端运行 `codex login status`，确认本机 Codex CLI 已登录；安装了 ChatGPT 桌面端时，应用也会自动检测其内置 Codex。
2. 打开“策略”或“建议”，点击右上角的“Codex 生成…”并确认。一次生成通常需要 1–3 分钟。
3. 生成期间 Codex 会读取当前持仓的名称、代码、类型、行业、折算市值与权重、现金比例、现有策略论点和最近三份行业研报摘要，并实时检索公开信息。
4. 策略结果会更新策略说明、风险阈值和当前持仓论点；建议结果会替换旧的待处理 Codex 建议。本地确定性风险规则、已经处理的 Codex 建议和决策历史会保留。

此链路复用本机 Codex 登录，不要求在 AI Invest 中保存另一份 OpenAI API Key。CLI 以只读沙盒、临时会话、禁止审批和严格 JSON Schema 运行；不会读取项目文件，也不会发送券商令牌、成本、盈亏或交易流水。结果只提供研究、核对与复盘动作，不执行交易。Codex CLI 参数及非交互模式可参阅 [OpenAI 官方命令参考](https://learn.chatgpt.com/docs/developer-commands?surface=cli)。

## 连接 Codex 学习

1. 在“学习”页点击“连接 Codex”，选择项目内的 `Learning` 文件夹。
2. 点击“同步 Codex 内容”，导入已经生成的课程。
3. 在课程内填写问题并选择“基于本课问 Codex”；或在“投资人方法”选择巴菲特、芒格、段永平后提问。应用会更新 `Learning/questions/current-context.md` 并复制提问。
4. 在 Codex 中粘贴问题。`$investment-learning-coach` 会读取本课、学习进度和个人方法论后回答。

默认不共享具体持仓。只有用户在学习页主动开启持仓上下文后，应用才会把代码、名称、资产类型和行业写入共享文件；数量、成本、资产总额、盈亏和交易记录仍不会写入。

## 数据与限制

- 数据库位置：`~/Library/Application Support/AIInvest/AIInvest.sqlite`。
- 当前长桥真实链路覆盖账户组合快照及持仓相关新闻；机构部分只覆盖官方公开材料。完整财务、估值、评级、公告全文和付费券商研报全文仍属于后续证据源扩展，不会在当前版本中伪装为已接入。
- 为让个人构建能够启动本机长桥官方终端，当前 Xcode target 关闭了 App Sandbox，但保留 Hardened Runtime。若未来分发到 Mac App Store，需要改为受支持的进程间集成方案并重新开启沙盒。
- 这是个人研究与资产管理工具，不构成投资建议，也不会自动交易。

完整需求和边界见 [MVP PRD](docs/AI_Invest_MVP_PRD.md)。

最近一次完整验收结果见 [产品可用性验收报告](docs/QA_REPORT.md)。
