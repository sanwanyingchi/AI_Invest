import SwiftUI

struct HoldingEditorContext: Identifiable {
    let id = UUID()
    let holding: Holding?
}

struct HoldingEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let holding: Holding?
    let baseCurrency: String
    let onSave: (Holding) -> Void

    @State private var assetType: AssetType
    @State private var name: String
    @State private var symbol: String
    @State private var sector: String
    @State private var currency: String
    @State private var shares: Double
    @State private var averageCost: Double
    @State private var lastPrice: Double
    @State private var dailyChangePercent: Double
    @State private var exchangeRateToBase: Double
    @State private var note: String

    init(holding: Holding?, baseCurrency: String, onSave: @escaping (Holding) -> Void) {
        self.holding = holding
        self.baseCurrency = baseCurrency
        self.onSave = onSave
        _assetType = State(initialValue: holding?.assetType ?? .fund)
        _name = State(initialValue: holding?.name ?? "")
        _symbol = State(initialValue: holding?.symbol ?? "")
        _sector = State(initialValue: holding?.sector ?? "")
        _currency = State(initialValue: holding?.currency ?? baseCurrency)
        _shares = State(initialValue: holding?.shares ?? 0)
        _averageCost = State(initialValue: holding?.averageCost ?? 0)
        _lastPrice = State(initialValue: holding?.lastPrice ?? 0)
        _dailyChangePercent = State(initialValue: holding?.dailyChangePercent ?? 0)
        _exchangeRateToBase = State(initialValue: holding?.exchangeRateToBase ?? 1)
        _note = State(initialValue: holding?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("资产信息") {
                    Picker("资产类型", selection: $assetType) {
                        ForEach(AssetType.allCases) { type in
                            Label(type.rawValue, systemImage: type.systemImage)
                                .tag(type)
                        }
                    }

                    TextField("资产名称", text: $name, prompt: Text("例如：某某基金 / Bitcoin"))
                    TextField("代码或标识", text: $symbol, prompt: Text("可选，例如 BTC、基金代码"))
                    TextField("行业或分类", text: $sector, prompt: Text("例如：数字资产、债券基金"))
                }

                Section("持仓与估值") {
                    TextField("持有数量", value: $shares, format: .number)
                    TextField("平均成本", value: $averageCost, format: .number)
                    TextField("当前价格 / 净值", value: $lastPrice, format: .number)
                    TextField("今日涨跌幅（%）", value: $dailyChangePercent, format: .number)
                }

                Section("币种换算") {
                    TextField("原始币种", text: $currency, prompt: Text("HKD / USD / CNY / USDT"))
                        .textCase(.uppercase)
                    TextField("1 原始币种 = 多少 \(baseCurrency)", value: $exchangeRateToBase, format: .number)

                    LabeledContent("折算市值") {
                        Text(AppFormat.money(convertedMarketValue, currency: baseCurrency))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }

                    Text("手动资产不会自动获得行情。更新价格、净值和汇率后，组合估值会立即重算。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("备注") {
                    TextField("托管平台、基金份额类别或其他说明", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(holding == nil ? "录入持仓" : "编辑持仓")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(holding == nil ? "添加" : "保存") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 660)
    }

    private var convertedMarketValue: Double {
        max(0, shares) * max(0, lastPrice) * max(0, exchangeRateToBase)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        shares.isFinite && averageCost.isFinite && lastPrice.isFinite &&
        dailyChangePercent.isFinite && exchangeRateToBase.isFinite &&
        shares > 0 && averageCost >= 0 && lastPrice >= 0 && exchangeRateToBase > 0 &&
        !currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard isValid else { return }
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSector = sector.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        onSave(
            Holding(
                id: holding?.id ?? UUID().uuidString,
                symbol: normalizedSymbol.isEmpty ? "手动资产" : normalizedSymbol,
                name: normalizedName,
                assetType: assetType,
                sector: normalizedSector.isEmpty ? assetType.rawValue : normalizedSector,
                currency: normalizedCurrency,
                shares: shares,
                availableShares: shares,
                averageCost: averageCost,
                lastPrice: lastPrice,
                dailyChangePercent: dailyChangePercent,
                exchangeRateToBase: exchangeRateToBase,
                source: .manual,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                updatedAt: .now
            )
        )
        dismiss()
    }
}
