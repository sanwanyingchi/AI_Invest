import Foundation

enum LearningCurriculum {
    static let units: [LearningUnit] = seeds.enumerated().map { index, seed in
        let day = index + 1
        return LearningUnit(
            id: String(format: "day-%02d", day),
            week: ((day - 1) / 7) + 1,
            day: day,
            track: seed.track,
            title: seed.title,
            objective: seed.objective,
            summary: seed.summary,
            keyPoints: seed.keyPoints,
            example: seed.example,
            exercise: seed.exercise,
            quiz: [
                LearningQuizQuestion(
                    id: String(format: "day-%02d-check", day),
                    prompt: seed.quizPrompt,
                    options: seed.options,
                    correctIndex: seed.correctIndex,
                    explanation: seed.explanation
                )
            ],
            reviewQuestions: [
                "不用术语，用一句话解释：\(seed.title)解决什么问题？",
                "这条知识会怎样改变你的真实投资流程？"
            ],
            suggestedCodexQuestions: [
                "请用一个港股例子重新解释“\(seed.title)”。",
                "请指出我完成今天练习时最容易犯的两个错误。",
                "请用反方观点挑战我对今天主题的理解。"
            ],
            source: .builtIn,
            generatedAt: nil
        )
    }

    static let defaultMethodology: [MethodologyNote] = MethodologySection.allCases.map {
        MethodologyNote(section: $0, content: $0.starter, updatedAt: .now)
    }

    static let investorProfiles: [InvestorThinkingProfile] = [
        InvestorThinkingProfile(
            id: "warren-buffett",
            name: "沃伦·巴菲特",
            identity: "企业所有者视角与长期资本配置",
            oneLineMethod: "把股票当作企业的一部分，在能力圈内评估长期经济性、管理层与价格。",
            principles: [
                "所有者思维：先理解企业如何长期创造每股价值，而不是预测短期股价。",
                "能力圈：不知道并不可怕，关键是清楚自己判断的边界。",
                "企业质量与资本配置：关注耐久竞争力、管理层诚信及资金使用效率。",
                "价格与价值分开：优秀企业仍需要可接受的价格和安全边际。",
                "长期伙伴关系：用多年经营结果而非月度行情检验判断。"
            ],
            decisionProcess: [
                "用简单语言说明客户为何持续付费，以及企业靠什么抵御竞争。",
                "检查利润能否转化为现金，管理层如何再投资、回购、分红或并购。",
                "写出内在价值区间的关键假设，并列出会令判断失效的变化。",
                "只有在理解范围内、价格可接受且能承受长期持有时继续研究。"
            ],
            usefulFor: [.stockSelection, .riskDiscipline, .decisionChecklist],
            limitations: [
                "伯克希尔拥有保险浮存金、永久资本、规模和交易渠道，个人投资者不能照搬其组合结构。",
                "长期持有不是永不复核；企业经济性、管理层或机会成本变化仍需重新判断。",
                "公开持仓披露滞后，学习方法不等于抄作业。"
            ],
            practiceQuestions: [
                "如果这家公司十年不能交易，我是否仍愿意依据经营结果持有？为什么？",
                "请用巴菲特的所有者视角审查我的选股评分卡，并指出证据不足的地方。",
                "我对这家公司的能力圈边界在哪里？哪些关键变量我实际上无法判断？"
            ],
            sources: [
                LearningSourceReference(
                    title: "Berkshire Hathaway 股东信档案",
                    publisher: "Berkshire Hathaway",
                    url: "https://www.berkshirehathaway.com/letters/letters.html",
                    note: "官方历年股东信；优先阅读原文并结合对应年份背景。"
                ),
                LearningSourceReference(
                    title: "An Owner's Manual",
                    publisher: "Berkshire Hathaway",
                    url: "https://www.berkshirehathaway.com/owners.html",
                    note: "官方所有者手册，说明伯克希尔的股东伙伴关系与经营原则。"
                )
            ],
            accentName: "blue"
        ),
        InvestorThinkingProfile(
            id: "charlie-munger",
            name: "查理·芒格",
            identity: "多学科心智模型与反向思考",
            oneLineMethod: "先避免明显错误，再用跨学科模型检查激励、概率和长期复利。",
            principles: [
                "多元心智模型：用经济学、心理学、数学和工程常识交叉验证判断。",
                "反向思考：先问什么会导致永久损失、欺诈或判断崩溃。",
                "激励机制：制度和报酬会系统性改变人的行为与信息质量。",
                "耐心与选择性：大多数时候等待，少数真正理解的机会才行动。",
                "避免愚蠢：降低杠杆、从众、确认偏误和复杂度带来的错误。"
            ],
            decisionProcess: [
                "把问题倒过来，列出最可能让结果失败的三条路径。",
                "检查参与者分别因为什么得到奖励，谁承担损失，信息是否被扭曲。",
                "至少用两个不同学科视角解释同一现象，寻找相互矛盾处。",
                "若风险无法清晰描述、杠杆会迫使行动或复杂度超出理解，选择不做。"
            ],
            usefulFor: [.industryResearch, .riskDiscipline, .decisionChecklist],
            limitations: [
                "心智模型不是术语清单；没有事实与数据支撑时，模型只会制造看似聪明的故事。",
                "高度集中和长期等待需要稳定现金流、心理承受力与极强研究能力，不适合机械复制。",
                "公开材料多为演讲与会议讨论，需区分原则、幽默表达和具体情境。"
            ],
            practiceQuestions: [
                "请对我的投资论点做一次反向检查：它最可能怎样失败？",
                "这家公司的客户、管理层、渠道和监管者分别受什么激励？",
                "请指出我正在使用的三个认知偏误，并设计一个验证动作。"
            ],
            sources: [
                LearningSourceReference(
                    title: "2023 Berkshire Hathaway 股东信",
                    publisher: "Berkshire Hathaway",
                    url: "https://www.berkshirehathaway.com/letters/2023ltr.pdf",
                    note: "官方材料，包含对芒格角色、原则与伯克希尔文化的回顾。"
                ),
                LearningSourceReference(
                    title: "Berkshire Hathaway 股东信档案",
                    publisher: "Berkshire Hathaway",
                    url: "https://www.berkshirehathaway.com/letters/letters.html",
                    note: "结合伯克希尔长期决策记录，观察原则如何落到资本配置。"
                )
            ],
            accentName: "purple"
        ),
        InvestorThinkingProfile(
            id: "duan-yongping",
            name: "段永平",
            identity: "商业模式、企业文化与本分",
            oneLineMethod: "买股票就是买公司；先看懂生意、文化和未来现金流，再谈价格与机会成本。",
            principles: [
                "买股票就是买公司：把注意力从交易价格转回企业未来创造的现金。",
                "商业模式：理解客户价值、差异化、长期盈利方式和资本需求。",
                "企业文化与本分：原则、诚信和长期行为会影响组织的经营质量。",
                "能力圈与不为清单：不懂的生意、无法承受的工具和短期预测可以直接放弃。",
                "平常心与机会成本：少受市场噪声影响，同时持续比较资金的长期用途。"
            ],
            decisionProcess: [
                "假设公司不上市，判断自己是否仍愿意以当前价格拥有这门生意。",
                "说明它为用户创造什么不可替代的价值，赚钱方式是否长期可持续。",
                "用管理层长期选择检验文化，而不是只采信口号或一次访谈。",
                "明确自己哪里看不懂，并把不做什么写进决策清单。"
            ],
            usefulFor: [.stockSelection, .riskDiscipline, .decisionChecklist],
            limitations: [
                "其公开表达以个人账户回复和访谈为主，内容零散且带具体语境；二次整理可能失真。",
                "企业家经验、集中度和风险承受能力与初学者不同，不能复制个股或仓位。",
                "“本分”“平常心”需要转换为可观察的治理、客户和资本配置证据，不能替代分析。"
            ],
            practiceQuestions: [
                "如果这家公司没有股票报价，我会用什么经营指标判断它变好还是变坏？",
                "请用商业模式、企业文化和机会成本三个角度挑战我的公司分析。",
                "我的不为清单还缺什么？哪些情境最容易让我越过能力圈？"
            ],
            sources: [
                LearningSourceReference(
                    title: "大道无形我有型公开主页",
                    publisher: "雪球",
                    url: "https://xueqiu.com/u/1247347556",
                    note: "段永平的公开发布入口；阅读时保留日期、上下文，并警惕转述失真。"
                ),
                LearningSourceReference(
                    title: "对话段永平：做自己能够喜欢的事情很重要",
                    publisher: "雪球《厚雪长波》",
                    url: "https://podcasts.apple.com/sg/podcast/id1689350648?i=1000736237745",
                    note: "雪球官方访谈的公开音频入口；用于理解完整语境，不作为买卖依据。"
                )
            ],
            accentName: "orange"
        )
    ]

    private struct Seed {
        let track: LearningTrack
        let title: String
        let objective: String
        let summary: String
        let keyPoints: [String]
        let example: String
        let exercise: String
        let quizPrompt: String
        let options: [String]
        let correctIndex: Int
        let explanation: String
    }

    private static let seeds: [Seed] = [
        Seed(
            track: .assetAllocation,
            title: "先定义目标，再谈收益",
            objective: "把投资目标写成金额、期限和可承受损失。",
            summary: "资产配置不是从“哪只股票会涨”开始，而是从资金用途和不能承受的结果开始。",
            keyPoints: ["不同期限的资金不能承担相同波动", "风险承受能力由财务能力和心理承受共同决定", "先排除不能亏损和短期要用的钱"],
            example: "两年内要支付首付的资金，不应因为看好港股就全部进入股票。",
            exercise: "写下一个具体目标、使用日期，以及你能接受的最大账面回撤。",
            quizPrompt: "制定配置方案时，第一步最应该确认什么？",
            options: ["下周最强行业", "资金目标、期限和损失承受能力", "热门股票名单"],
            correctIndex: 1,
            explanation: "目标、期限和风险边界决定可使用的资产与仓位。"
        ),
        Seed(
            track: .assetAllocation,
            title: "风险不是波动这么简单",
            objective: "区分永久损失、流动性风险和短期波动。",
            summary: "稳健不等于价格不动，而是组合在不利情况下仍不会破坏你的生活和长期计划。",
            keyPoints: ["短期波动可能恢复，永久损失通常来自基本面恶化或高价买入", "流动性不足会迫使你在坏时点卖出", "杠杆会放大波动并制造被迫卖出"],
            example: "优质公司下跌20%与高负债公司失去偿债能力，是两种不同风险。",
            exercise: "把你最担心的三种亏损场景分别归类。",
            quizPrompt: "哪种情况最接近永久损失风险？",
            options: ["指数一天回调2%", "公司竞争优势消失且现金流持续恶化", "汇率日内波动"],
            correctIndex: 1,
            explanation: "长期盈利能力受损会直接破坏资产内在价值。"
        ),
        Seed(
            track: .assetAllocation,
            title: "理解不同资产的角色",
            objective: "为股票、基金、债券、现金和高波动资产分配明确职责。",
            summary: "资产类别不是收藏品；每一种资产都应在组合中承担增长、防守、流动性或可选机会的角色。",
            keyPoints: ["股票承担长期增长但波动较大", "现金提供流动性和再平衡能力", "债券或稳健基金用于降低组合波动", "高波动资产必须设置严格上限"],
            example: "现金仓不是“没有投资”，而是应急、等待机会和避免被迫卖出的工具。",
            exercise: "给你当前每类资产写一个存在理由；没有理由的标记为待复核。",
            quizPrompt: "现金在稳健组合中的核心作用是什么？",
            options: ["保证最高收益", "提供流动性和应对不确定性", "预测市场顶部"],
            correctIndex: 1,
            explanation: "现金的价值主要是流动性、风险缓冲和再平衡选择权。"
        ),
        Seed(
            track: .assetAllocation,
            title: "分散真正分散的风险",
            objective: "理解相关性，避免“持有很多只但风险来源相同”。",
            summary: "标的数量不等于有效分散；应检查行业、地区、商业模式和宏观驱动是否重复。",
            keyPoints: ["同一行业多只股票可能同步下跌", "ETF也可能与个股形成底层重叠", "分散的目标是降低单一判断错误的伤害"],
            example: "同时持有多家香港银行，看似多只股票，实质仍集中于利率和信用周期。",
            exercise: "按风险驱动而不是股票代码给当前持仓分组。",
            quizPrompt: "哪一种组合更可能存在伪分散？",
            options: ["现金、债券基金和全球股票ETF", "五家业务相似的银行", "不同行业的低相关资产"],
            correctIndex: 1,
            explanation: "业务和宏观驱动高度相似时，标的数量不会带来足够分散。"
        ),
        Seed(
            track: .assetAllocation,
            title: "确定目标配置与仓位上限",
            objective: "把稳健风格转化为可检查的比例和红线。",
            summary: "目标配置给出正常状态，仓位上限限制单一错误可能造成的最大伤害。",
            keyPoints: ["同时设置目标比例与允许区间", "单一股票、行业和高波动资产分别设上限", "上限应由总资产风险而非主观信心决定"],
            example: "目标股票60%，允许区间55%–65%；单一个股不超过20%，规则比临场感觉更稳定。",
            exercise: "写出你的资产目标比例、允许区间和三条集中度红线。",
            quizPrompt: "仓位上限主要解决什么问题？",
            options: ["保证每次买在最低点", "控制单一判断错误的组合伤害", "提高交易频率"],
            correctIndex: 1,
            explanation: "上限是风险预算，不是对标的涨跌的预测。"
        ),
        Seed(
            track: .assetAllocation,
            title: "用再平衡代替择时冲动",
            objective: "建立按时间或偏离幅度执行的再平衡规则。",
            summary: "再平衡的目的，是让风险回到计划内，而不是准确预测市场顶部和底部。",
            keyPoints: ["可按季度检查，也可按偏离阈值触发", "优先使用新增资金和现金调整", "交易成本和税费应进入决策"],
            example: "目标股票60%，当权重高于65%时复核并恢复到区间，而不是因一天上涨就卖出。",
            exercise: "选择一种检查频率和一个偏离阈值，写入方法论。",
            quizPrompt: "再平衡最合理的目标是什么？",
            options: ["预测短期涨跌", "恢复计划中的风险水平", "追逐最近表现最强的资产"],
            correctIndex: 1,
            explanation: "再平衡服务于风险纪律，而不是短线择时。"
        ),
        Seed(
            track: .assetAllocation,
            title: "完成资产配置 v1.0",
            objective: "产出一页可执行的个人资产配置方案。",
            summary: "把目标、比例、上限和再平衡合并成一份能在市场波动时直接执行的规则。",
            keyPoints: ["说明每类资产存在的理由", "写明正常区间和红线", "提前定义极端行情中的动作和不做的事"],
            example: "一页方案比十页市场预测更容易在压力下执行。",
            exercise: "完成“资产配置规则”页面，并检查比例是否合计100%。",
            quizPrompt: "一份可执行的配置方案最不能缺少什么？",
            options: ["每周指数目标点位", "目标比例、允许区间与再平衡规则", "十只热门股"],
            correctIndex: 1,
            explanation: "比例、边界和触发规则构成可执行配置。"
        ),
        Seed(
            track: .stockSelection,
            title: "先看懂公司怎么赚钱",
            objective: "用客户、产品、定价和成本解释商业模式。",
            summary: "如果无法简洁解释收入来源和关键成本，就还没有进入可以估值和判断的阶段。",
            keyPoints: ["谁付钱、为什么付钱", "收入是一次性还是重复性", "增长是否需要持续投入大量资本"],
            example: "交易所的收入受成交、上市和投资收益驱动，与零售公司的驱动完全不同。",
            exercise: "用不超过100字解释一家持仓公司的赚钱方式。",
            quizPrompt: "分析公司商业模式时最先问什么？",
            options: ["股价明天会不会涨", "客户为什么付钱，公司如何留下利润", "社交媒体讨论量"],
            correctIndex: 1,
            explanation: "商业模式决定收入、成本、竞争和现金流的来源。"
        ),
        Seed(
            track: .stockSelection,
            title: "三张财务报表只抓主线",
            objective: "理解利润表、资产负债表和现金流量表如何互相验证。",
            summary: "利润说明一段时间的经营结果，资产负债表说明家底，现金流说明利润有没有变成钱。",
            keyPoints: ["净利润不等于经营现金流", "债务和现金决定抗风险能力", "报表之间长期背离需要解释"],
            example: "利润增长但应收账款和库存快速上升，可能意味着增长质量下降。",
            exercise: "找到一家公司最近一期三张报表，各写一个最重要数字。",
            quizPrompt: "哪张报表最直接展示期末债务和现金？",
            options: ["利润表", "资产负债表", "现金流量表"],
            correctIndex: 1,
            explanation: "资产负债表展示某一时点的资产、负债和权益。"
        ),
        Seed(
            track: .stockSelection,
            title: "判断利润质量",
            objective: "用现金流、资本投入和一次性项目验证盈利。",
            summary: "高质量利润通常能转化为现金，并且不依赖持续高额投入或一次性收益。",
            keyPoints: ["经营现金流长期应与利润相匹配", "自由现金流要扣除维持经营所需资本开支", "剔除出售资产等一次性收益"],
            example: "账面利润稳定但多年自由现金流为负，需要判断是扩张投资还是商业模式问题。",
            exercise: "比较目标公司三年净利润与经营现金流趋势。",
            quizPrompt: "以下哪项最能提高对利润质量的信心？",
            options: ["利润与经营现金流长期匹配", "依赖出售资产增加利润", "应收账款远快于收入增长"],
            correctIndex: 0,
            explanation: "现金转化良好通常说明利润更接近真实经营成果。"
        ),
        Seed(
            track: .stockSelection,
            title: "寻找护城河，而不是好故事",
            objective: "识别品牌、网络效应、转换成本、规模和成本优势。",
            summary: "护城河必须能够阻止竞争侵蚀回报，并在数据或客户行为中留下证据。",
            keyPoints: ["高利润率本身不是护城河", "优势要能持续并难以复制", "竞争优势最终应体现在定价、留存或资本回报"],
            example: "平台用户多不一定有网络效应，关键是新用户是否让其他用户获得更多价值。",
            exercise: "为一家公司写出护城河证据和一个可能推翻它的信号。",
            quizPrompt: "哪项更像可验证的护城河证据？",
            options: ["公司说自己是行业领先", "客户留存高且提价后流失仍低", "近期股价上涨"],
            correctIndex: 1,
            explanation: "客户行为和定价能力比管理层口号更能验证竞争优势。"
        ),
        Seed(
            track: .stockSelection,
            title: "评估管理层与资本配置",
            objective: "判断管理层如何使用股东资金，以及承诺是否兑现。",
            summary: "管理层质量最终体现在资本配置、信息透明度和长期每股价值，而不是演讲风格。",
            keyPoints: ["比较过去承诺与实际结果", "检查并购、回购、分红和再投资回报", "警惕频繁调整口径和过度激励"],
            example: "低估时回购可能创造价值，高估时为拉升每股利润而回购可能浪费资本。",
            exercise: "找出目标公司过去三年最大的两项资本配置决策。",
            quizPrompt: "评价回购是否合理，最关键看什么？",
            options: ["回购新闻是否热门", "回购价格与内在价值及资金机会成本", "回购次数越多越好"],
            correctIndex: 1,
            explanation: "资本配置要比较支付价格、内在价值和其他资金用途。"
        ),
        Seed(
            track: .stockSelection,
            title: "估值与安全边际",
            objective: "理解好公司也可能因为价格过高而成为差投资。",
            summary: "估值是对未来现金流和风险的假设集合；安全边际用于容纳判断误差。",
            keyPoints: ["市盈率必须结合增长、周期和资本结构", "使用区间而不是单点目标价", "先写关键假设，再看模型结果"],
            example: "周期顶部的低市盈率可能来自暂时高利润，并不一定便宜。",
            exercise: "写出影响目标公司估值最大的三个假设，并给出悲观情景。",
            quizPrompt: "安全边际主要保护投资者免受什么影响？",
            options: ["所有短期波动", "估值与基本面判断误差", "错过每一次上涨"],
            correctIndex: 1,
            explanation: "以低于保守价值估计的价格买入，为不可避免的误差留空间。"
        ),
        Seed(
            track: .stockSelection,
            title: "完成选股评分卡 v1.0",
            objective: "建立从能力圈到证伪条件的统一筛选流程。",
            summary: "评分卡的意义不是制造精确分数，而是确保每家公司经过相同问题和风险检查。",
            keyPoints: ["先设硬性排除项，再做评分", "事实、判断和未知项分开记录", "最终状态使用排除、观察、候选和持有"],
            example: "不理解商业模式或无法判断债务风险，可以直接进入观察而不是勉强打高分。",
            exercise: "完成“选股评分卡”，并用它评估一家真实港股公司。",
            quizPrompt: "评分卡最重要的价值是什么？",
            options: ["替代所有主观判断", "让不同标的接受一致、可复核的检查", "保证选中上涨股票"],
            correctIndex: 1,
            explanation: "一致流程能降低遗漏、情绪和事后合理化。"
        ),
        Seed(
            track: .industryResearch,
            title: "画出行业价值链",
            objective: "知道钱从哪里来、流向哪里，以及谁拥有议价权。",
            summary: "先看上下游和利润分布，才能理解行业增长最终会被哪些公司转化为股东回报。",
            keyPoints: ["列出供应商、生产者、渠道和客户", "区分收入规模与利润池", "寻找控制稀缺资源或客户入口的一方"],
            example: "电商增长不代表所有环节同等受益，平台、物流和品牌的利润结构不同。",
            exercise: "用四到六个节点画出一个感兴趣行业的价值链。",
            quizPrompt: "行业价值链分析最想回答什么？",
            options: ["哪家公司名字最好听", "价值如何创造、传递和被谁获取", "指数明天点位"],
            correctIndex: 1,
            explanation: "价值链帮助定位利润池和议价权。"
        ),
        Seed(
            track: .industryResearch,
            title: "判断行业发展阶段",
            objective: "区分导入、成长、成熟和衰退阶段的不同逻辑。",
            summary: "同一个增速在不同渗透率、竞争和资本投入背景下，投资含义完全不同。",
            keyPoints: ["成长阶段关注渗透率和份额", "成熟阶段关注现金流、效率和资本回报", "衰退行业要警惕价值陷阱"],
            example: "行业总量不再高速增长时，龙头仍可能通过份额提升和效率改善创造价值。",
            exercise: "判断一个行业所处阶段，并列出两条证据。",
            quizPrompt: "成熟行业通常更应关注什么？",
            options: ["只有市场规模增速", "现金流、份额和资本回报", "概念数量"],
            correctIndex: 1,
            explanation: "成熟阶段的价值更多来自效率、份额和股东回报。"
        ),
        Seed(
            track: .industryResearch,
            title: "拆解供需与周期",
            objective: "识别价格、库存、产能和需求之间的反馈。",
            summary: "周期行业的高利润会吸引供给，低利润会淘汰产能；不能把周期高点线性外推。",
            keyPoints: ["需求变化和供给弹性共同决定价格", "库存是连接供需的重要信号", "新增产能通常有时间滞后"],
            example: "商品价格上涨后大量扩产，产能投放时可能遇到需求放缓。",
            exercise: "为一个周期行业列出需求指标、供给指标和库存指标。",
            quizPrompt: "分析周期行业时，为什么不能只看当前利润？",
            options: ["利润没有任何意义", "当前高利润可能刺激未来供给并回落", "财务报表不公开"],
            correctIndex: 1,
            explanation: "供给响应和时间滞后会让高利润具有周期性。"
        ),
        Seed(
            track: .industryResearch,
            title: "看竞争格局与集中度",
            objective: "判断企业增长来自行业红利还是竞争优势。",
            summary: "行业增长很快但竞争激烈、进入壁垒低，股东未必获得高回报。",
            keyPoints: ["观察市场份额及其变化", "分析进入壁垒、替代品和价格竞争", "集中度高不自动等于竞争温和"],
            example: "少数玩家也可能进行激烈价格战，因此还要看定价行为和产能纪律。",
            exercise: "列出行业前三家公司、份额趋势和主要竞争手段。",
            quizPrompt: "行业高速增长一定意味着股东高回报吗？",
            options: ["一定", "不一定，还要看竞争和资本投入", "只要媒体关注就一定"],
            correctIndex: 1,
            explanation: "竞争可能把增长价值转移给客户或供应商。"
        ),
        Seed(
            track: .industryResearch,
            title: "找到少数关键指标",
            objective: "用三到五个指标持续跟踪行业，而不是收集所有数据。",
            summary: "好指标应接近经济驱动、可持续获得，并能比利润更早显示变化。",
            keyPoints: ["区分结果指标与领先指标", "指标定义必须保持一致", "建立正常区间和异常解释"],
            example: "保险行业可关注新业务价值、代理人生产力和续保质量，而不只看收入。",
            exercise: "为一个行业选择三项核心指标，并解释它们领先什么。",
            quizPrompt: "选择行业指标时最重要的标准是什么？",
            options: ["数量越多越好", "能解释核心经济驱动且可持续跟踪", "只选公司最常宣传的数字"],
            correctIndex: 1,
            explanation: "少数稳定、因果关系清晰的指标更适合持续跟踪。"
        ),
        Seed(
            track: .industryResearch,
            title: "识别政策、技术与替代风险",
            objective: "提前写出会改变行业结构的外部变量和证伪信号。",
            summary: "行业风险不是附录，而是决定利润池是否存在、持续多久的核心假设。",
            keyPoints: ["政策可能改变准入、价格和资本要求", "技术可能降低成本也可能摧毁壁垒", "替代品风险要从客户选择出发"],
            example: "监管要求提高可能短期增加成本，也可能长期提高行业进入壁垒。",
            exercise: "写出一个行业的三种结构性风险和可观察信号。",
            quizPrompt: "有效的风险描述应该包含什么？",
            options: ["只写“市场有风险”", "风险机制、影响路径和观察信号", "只写最坏结果"],
            correctIndex: 1,
            explanation: "可观察的影响路径才能用于后续验证。"
        ),
        Seed(
            track: .industryResearch,
            title: "完成行业模板 v1.0",
            objective: "把价值链、阶段、供需、竞争、指标和风险合成一页模板。",
            summary: "统一模板使不同时间和不同行业的研究可以比较，也能暴露证据缺口。",
            keyPoints: ["事实与观点分开", "每个结论标注来源和日期", "明确哪些变化会推翻当前判断"],
            example: "模板结尾必须是跟踪清单，而不是笼统的“长期看好”。",
            exercise: "完成“行业分析模板”，并选择下周要实践的港股行业。",
            quizPrompt: "行业报告结尾最有用的内容是什么？",
            options: ["更多形容词", "关键指标、证伪条件和跟踪计划", "股价保证"],
            correctIndex: 1,
            explanation: "研究必须能进入持续验证和决策流程。"
        ),
        Seed(
            track: .integration,
            title: "完成一份行业快照",
            objective: "用统一模板研究一个与你持仓有关的行业。",
            summary: "综合实践从行业开始，避免脱离竞争和周期孤立分析公司。",
            keyPoints: ["控制在一页核心结论", "至少使用两类可靠来源", "列出三个后续跟踪指标"],
            example: "金融行业可以拆分银行、保险和交易所，不能因为同属金融就混为一谈。",
            exercise: "完成目标行业的一页快照并保存到学习笔记。",
            quizPrompt: "行业快照为什么要限制核心结论数量？",
            options: ["为了省字", "迫使研究聚焦真正影响判断的驱动", "因为数据不重要"],
            correctIndex: 1,
            explanation: "聚焦关键驱动能让研究直接服务决策。"
        ),
        Seed(
            track: .integration,
            title: "完成一家公司分析",
            objective: "从商业模式、财务、护城河、管理层、估值和风险形成结论。",
            summary: "公司分析必须包含反方证据和未知项，不能只是为现有持仓寻找支持。",
            keyPoints: ["先写事实，再写推断", "至少提出一个反方情景", "给出排除、观察、候选或持有状态"],
            example: "“好公司”是质量判断，“当前值得买”还必须加入价格和组合风险。",
            exercise: "选择一家港股公司，使用选股评分卡完成首次评估。",
            quizPrompt: "公司质量高是否足以得出买入结论？",
            options: ["足够", "不够，还要考虑价格、风险和组合适配", "只要是龙头就足够"],
            correctIndex: 1,
            explanation: "投资结论需要质量、估值和组合风险共同支持。"
        ),
        Seed(
            track: .integration,
            title: "比较两家公司",
            objective: "在同一行业内用相同口径比较质量、估值和风险。",
            summary: "相对比较能发现单看一家时忽略的商业模式差异和隐含估值假设。",
            keyPoints: ["统一会计和经营指标口径", "解释差异而不只排列数字", "比较最关键的风险回报权衡"],
            example: "两家保险公司的新业务价值增速相同，但渠道质量和资本需求可能不同。",
            exercise: "用评分卡比较两家公司，并写出为什么暂时选择其中一家继续跟踪。",
            quizPrompt: "公司比较中最应避免什么？",
            options: ["统一口径", "只比较估值倍数而忽略业务质量差异", "解释指标差异"],
            correctIndex: 1,
            explanation: "估值倍数只有结合业务质量、周期和风险才有意义。"
        ),
        Seed(
            track: .integration,
            title: "审计当前组合",
            objective: "检查配置、集中度、重复风险和每项持仓存在理由。",
            summary: "组合审计关注持仓之间如何共同作用，而不是逐只判断是否看好。",
            keyPoints: ["检查单一持仓和行业集中", "识别ETF与个股底层重叠", "每项持仓都要有角色与退出条件"],
            example: "多只金融股加恒指ETF，实际金融暴露可能高于持仓名称给人的直觉。",
            exercise: "对当前组合写出三个主要风险和一个不需要立刻行动的理由。",
            quizPrompt: "组合审计的单位是什么？",
            options: ["只看单只股票", "整个组合的共同风险与目标适配", "只看当日盈亏"],
            correctIndex: 1,
            explanation: "资产间相关性和叠加风险只有在组合层面可见。"
        ),
        Seed(
            track: .integration,
            title: "建立买入、持有与退出规则",
            objective: "在行动前定义触发条件，减少情绪化和事后合理化。",
            summary: "规则不能替代判断，但能确保判断在证据改变时及时重做。",
            keyPoints: ["买入条件包含质量、价格和仓位", "持有期间跟踪关键假设", "退出优先由论点失效和风险超限触发"],
            example: "股价下跌不是自动卖出理由；若下跌来自核心论点被证伪，则应复核。",
            exercise: "为一个真实持仓写出买入理由、三个跟踪信号和两个退出条件。",
            quizPrompt: "哪项最适合作为退出复核触发？",
            options: ["任何一天股价下跌", "核心盈利假设被持续数据证伪", "朋友改变看法"],
            correctIndex: 1,
            explanation: "退出应关联投资论点和风险预算，而非单日价格噪声。"
        ),
        Seed(
            track: .integration,
            title: "给组合做压力测试",
            objective: "预演市场下跌、行业冲击和流动性需求下的组合表现。",
            summary: "压力测试不追求准确预测，而是发现你承受不起的暴露和被迫行动。",
            keyPoints: ["至少测试市场、行业和个人现金需求三类情景", "估计损失区间而非精确点位", "预先写出会做和不会做的事"],
            example: "若港股整体下跌30%、主要行业跌40%，组合回撤是否超过你的财务和心理边界？",
            exercise: "完成一个悲观情景，检查现金是否足够、是否会被迫卖出。",
            quizPrompt: "压力测试的核心价值是什么？",
            options: ["精确预测危机日期", "提前发现不可承受风险并准备行动", "证明组合不会亏损"],
            correctIndex: 1,
            explanation: "压力测试用于准备而非预测。"
        ),
        Seed(
            track: .integration,
            title: "定稿个人投资手册 v1.0",
            objective: "把四周成果整理成一套清晰、可执行、可复盘的方法论。",
            summary: "v1.0不是终点；它是一套有版本、能被真实决策检验并持续修订的个人系统。",
            keyPoints: ["资产配置、选股、行业和决策纪律互相一致", "规则必须具体到可检查", "每月小复盘、每季度版本更新"],
            example: "方法论允许写“目前不知道”，但不能把愿望写成事实。",
            exercise: "逐项检查五个方法论页面，补齐空白并写下下次复盘日期。",
            quizPrompt: "个人投资手册最合理的使用方式是什么？",
            options: ["完成后永不修改", "在真实决策和复盘中持续迭代", "用来保证收益"],
            correctIndex: 1,
            explanation: "方法论需要接受实践检验，并随认知和目标变化更新。"
        )
    ]
}
