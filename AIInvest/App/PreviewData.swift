import Foundation

enum PreviewData {
    static let holdings: [Holding] = [
        Holding(
            symbol: "700.HK",
            name: "腾讯控股",
            sector: "资讯科技",
            currency: "HKD",
            shares: 800,
            availableShares: 800,
            averageCost: 520.00,
            lastPrice: 600.00,
            dailyChangePercent: 1.20
        ),
        Holding(
            symbol: "1299.HK",
            name: "友邦保险",
            sector: "金融",
            currency: "HKD",
            shares: 2_500,
            availableShares: 2_500,
            averageCost: 72.00,
            lastPrice: 78.35,
            dailyChangePercent: -0.60
        ),
        Holding(
            symbol: "5.HK",
            name: "汇丰控股",
            sector: "金融",
            currency: "HKD",
            shares: 1_800,
            availableShares: 1_800,
            averageCost: 88.00,
            lastPrice: 104.80,
            dailyChangePercent: 0.40
        ),
        Holding(
            symbol: "2800.HK",
            name: "盈富基金",
            assetType: .etf,
            sector: "ETF",
            currency: "HKD",
            shares: 6_000,
            availableShares: 6_000,
            averageCost: 26.80,
            lastPrice: 28.40,
            dailyChangePercent: -0.20
        ),
        Holding(
            symbol: "388.HK",
            name: "香港交易所",
            sector: "金融",
            currency: "HKD",
            shares: 300,
            availableShares: 300,
            averageCost: 410.00,
            lastPrice: 468.00,
            dailyChangePercent: 0.90
        ),
        Holding(
            id: "preview-manual-fund",
            symbol: "FUND-USD",
            name: "稳健收益基金（示例）",
            assetType: .fund,
            sector: "多元基金",
            currency: "USD",
            shares: 120,
            availableShares: 120,
            averageCost: 95,
            lastPrice: 102,
            dailyChangePercent: 0.12,
            exchangeRateToBase: 7.80,
            source: .manual,
            note: "用于演示无法从长桥同步的基金持仓"
        ),
        Holding(
            id: "preview-manual-btc",
            symbol: "BTC",
            name: "Bitcoin（示例）",
            assetType: .crypto,
            sector: "数字资产",
            currency: "USD",
            shares: 0.12,
            availableShares: 0.12,
            averageCost: 58_000,
            lastPrice: 63_500,
            dailyChangePercent: 1.65,
            exchangeRateToBase: 7.80,
            source: .manual,
            note: "用于演示加密货币手动估值"
        )
    ]

    static let rules: [StrategyRule] = [
        StrategyRule(
            id: "single-position",
            title: "单一持仓上限",
            description: "任一股票市值不超过组合净资产的 30%",
            currentValue: "35.2%",
            limitValue: "≤ 30%",
            state: .warning
        ),
        StrategyRule(
            id: "sector-position",
            title: "单一行业上限",
            description: "避免风险过度集中在同一行业",
            currentValue: "38.6%",
            limitValue: "≤ 40%",
            state: .warning
        ),
        StrategyRule(
            id: "cash-buffer",
            title: "现金缓冲",
            description: "为波动和后续机会保留流动性",
            currentValue: "12.0%",
            limitValue: "≥ 10%",
            state: .healthy
        ),
        StrategyRule(
            id: "leverage",
            title: "杠杆与复杂产品",
            description: "MVP 稳健策略禁止杠杆、卖空和期权",
            currentValue: "未使用",
            limitValue: "禁止",
            state: .healthy
        )
    ]

    static let theses: [InvestmentThesis] = [
        InvestmentThesis(
            symbol: "700.HK",
            companyName: "腾讯控股",
            summary: "核心业务现金流稳健，视频号与高质量增长有望支持利润率。",
            keyEvidence: "经营利润保持增长，回购持续，现金流质量较好。",
            nextReviewAt: date(daysFromNow: 14),
            health: .supported
        ),
        InvestmentThesis(
            symbol: "1299.HK",
            companyName: "友邦保险",
            summary: "亚洲保险渗透率仍有空间，关注新业务价值和代理人生产力。",
            keyEvidence: "需要核对最新新业务价值指引与地区结构变化。",
            nextReviewAt: date(daysFromNow: 5),
            health: .review
        ),
        InvestmentThesis(
            symbol: "5.HK",
            companyName: "汇丰控股",
            summary: "资本回报与股东分派构成主要持有逻辑。",
            keyEvidence: "净息差可能随利率周期变化，需要持续观察。",
            nextReviewAt: date(daysFromNow: 20),
            health: .supported
        ),
        InvestmentThesis(
            symbol: "2800.HK",
            companyName: "盈富基金",
            summary: "作为港股市场的低成本分散配置与流动性仓位。",
            keyEvidence: "跟踪指数，不以个股基本面作为核心论点。",
            nextReviewAt: date(daysFromNow: 30),
            health: .supported
        ),
        InvestmentThesis(
            symbol: "388.HK",
            companyName: "香港交易所",
            summary: "待补充结构化投资论点。",
            keyEvidence: "需要明确成交活跃度、产品结构和估值假设。",
            nextReviewAt: date(daysFromNow: 2),
            health: .missing
        )
    ]

    static let strategy = InvestmentStrategy(
        id: "steady-hk",
        name: "稳健港股",
        description: "以基本面、分散配置和风险纪律为核心，避免被单日行情推动交易。",
        riskProfile: "稳健 · 中低频",
        updatedAt: date(daysFromNow: -3),
        rules: rules,
        theses: theses
    )

    static let advice: [AdviceItem] = [
        AdviceItem(
            id: "advice-concentration",
            title: "复核腾讯持仓集中度",
            summary: "腾讯当前权重高于策略建议值，先核对论点与组合容忍度，不直接给出减仓结论。",
            relatedObject: "腾讯控股 · 700.HK",
            trigger: "单一持仓权重接近或超过 30% 阈值",
            evidence: ["当前估算权重 35.2%", "策略上限 30%", "论点状态：有效"],
            counterEvidence: "现金缓冲充足，且当前没有论点失效证据。",
            priority: .high,
            status: .pending,
            confidence: "高",
            createdAt: date(hoursFromNow: -2),
            validUntil: date(daysFromNow: 7)
        ),
        AdviceItem(
            id: "advice-aia-thesis",
            title: "更新友邦保险投资论点",
            summary: "下一次复核时间临近，建议确认新业务价值与地区结构变化。",
            relatedObject: "友邦保险 · 1299.HK",
            trigger: "投资论点将在 5 天后到期",
            evidence: ["最近复核距今 86 天", "下一次财务事件临近"],
            counterEvidence: "目前没有发现重大负面公告。",
            priority: .medium,
            status: .pending,
            confidence: "中",
            createdAt: date(hoursFromNow: -5),
            validUntil: date(daysFromNow: 5)
        ),
        AdviceItem(
            id: "advice-hkex-thesis",
            title: "补充港交所持仓理由",
            summary: "该持仓缺少结构化论点，后续建议将难以判断新证据是否重要。",
            relatedObject: "香港交易所 · 388.HK",
            trigger: "持仓没有完整投资论点",
            evidence: ["买入理由为空", "失效条件为空"],
            counterEvidence: "持仓权重较低，当前不构成紧急组合风险。",
            priority: .low,
            status: .pending,
            confidence: "高",
            createdAt: date(daysFromNow: -1),
            validUntil: date(daysFromNow: 14)
        ),
        AdviceItem(
            id: "advice-cash",
            title: "现金缓冲符合策略",
            summary: "现金占比高于最低要求，本周无需额外处理。",
            relatedObject: "组合",
            trigger: "每周流动性检查",
            evidence: ["现金权重约 12%", "策略下限 10%"],
            counterEvidence: "若市场大幅波动，现金占比会随市值变化。",
            priority: .low,
            status: .completed,
            confidence: "高",
            createdAt: date(daysFromNow: -5),
            validUntil: date(daysFromNow: 2)
        )
    ]

    static let schedules: [ResearchSchedule] = [
        ResearchSchedule(
            id: "schedule-holdings-weekly",
            name: "持仓行业周报",
            industryScope: "全部持仓行业",
            template: .weekly,
            nextRunAt: nextSaturdayAtTen,
            lastRunAt: date(daysFromNow: -7),
            isEnabled: true,
            state: .ready,
            modelName: "本地模拟",
            monthlyBudget: 100
        )
    ]

    static let reports: [IndustryReport] = [
        IndustryReport(
            id: "report-finance-weekly",
            title: "金融行业周报｜利率预期与资本回报",
            industry: "金融",
            executiveSummary: "本周行业表现平稳，市场继续关注利率路径、保险新业务价值和银行资本分派。",
            changes: [
                "保险板块盈利预期整体稳定。",
                "银行板块的净息差预期仍是主要分歧。",
                "港交所成交活跃度有所改善，但估值仍需结合盈利兑现。"
            ],
            portfolioImpact: "组合金融行业权重接近策略上限，新增仓位前应先复核行业集中度。",
            counterEvidence: "当前数据为模拟展示，正式结论需等待长桥真实数据和原始来源校验。",
            sources: ["长桥行业排名", "机构一致预期", "公司公告摘要"],
            periodStart: date(daysFromNow: -7),
            periodEnd: date(daysFromNow: -1),
            generatedAt: date(daysFromNow: -1),
            modelName: "GPT（模拟）",
            isUnread: true
        ),
        IndustryReport(
            id: "report-tech-weekly",
            title: "资讯科技周报｜盈利质量保持稳定",
            industry: "资讯科技",
            executiveSummary: "龙头公司现金流和资本回报仍是本期重点，暂无足以改变持仓论点的新证据。",
            changes: [
                "市场关注从收入增速转向盈利质量。",
                "主要机构评级分布没有明显方向变化。",
                "回购和股东回报继续提供估值支撑。"
            ],
            portfolioImpact: "腾讯权重较高，行业观点稳定不代表集中度风险消失。",
            counterEvidence: "政策、竞争和新业务投入仍可能影响利润率。",
            sources: ["长桥机构评级", "一致预期", "公司新闻摘要"],
            periodStart: date(daysFromNow: -14),
            periodEnd: date(daysFromNow: -8),
            generatedAt: date(daysFromNow: -8),
            modelName: "GPT（模拟）",
            isUnread: false
        )
    ]

    static func workspace(updatedAt: Date = date(minutesFromNow: -12)) -> WorkspacePayload {
        WorkspacePayload(
            portfolio: PortfolioSnapshot(
                holdings: holdings,
                cash: 185_000,
                currency: "HKD",
                updatedAt: updatedAt
            ),
            strategy: strategy,
            advice: advice,
            schedules: schedules,
            reports: reports
        )
    }

    private static var nextSaturdayAtTen: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong") ?? .current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let daysUntilSaturday = (7 - weekday + 7) % 7
        let day = calendar.date(byAdding: .day, value: daysUntilSaturday == 0 ? 7 : daysUntilSaturday, to: now) ?? now
        return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
    }

    private static func date(daysFromNow days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .now
    }

    private static func date(hoursFromNow hours: Int) -> Date {
        Calendar.current.date(byAdding: .hour, value: hours, to: .now) ?? .now
    }

    private static func date(minutesFromNow minutes: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: .now) ?? .now
    }
}
