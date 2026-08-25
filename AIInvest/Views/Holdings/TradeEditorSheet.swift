import SwiftUI

struct TradeEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let holdings: [Holding]
    let baseCurrency: String
    let onSave: (RecordedTrade, Bool, Bool) -> String?

    @State private var selectedHoldingID: String
    @State private var side: TradeSide = .buy
    @State private var quantity: Double = 0
    @State private var price: Double
    @State private var fees: Double = 0
    @State private var exchangeRateToBase: Double
    @State private var tradedAt = Date()
    @State private var note = ""
    @State private var applyToPosition: Bool
    @State private var applyToCash = false
    @State private var errorMessage: String?

    init(
        holdings: [Holding],
        baseCurrency: String,
        onSave: @escaping (RecordedTrade, Bool, Bool) -> String?
    ) {
        self.holdings = holdings
        self.baseCurrency = baseCurrency
        self.onSave = onSave
        let initialHolding = holdings.first
        _selectedHoldingID = State(initialValue: initialHolding?.id ?? "")
        _price = State(initialValue: initialHolding?.lastPrice ?? 0)
        _exchangeRateToBase = State(initialValue: initialHolding?.exchangeRateToBase ?? 1)
        _applyToPosition = State(initialValue: initialHolding?.source == .manual)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("交易标的") {
                    Picker("持仓", selection: $selectedHoldingID) {
                        ForEach(holdings) { holding in
                            Text("\(holding.name) · \(holding.symbol) · \(holding.source == .manual ? "手动" : "长桥")")
                                .tag(holding.id)
                        }
                    }

                    Picker("方向", selection: $side) {
                        ForEach(TradeSide.allCases) { side in
                            Text(side.rawValue).tag(side)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("成交信息") {
                    DatePicker("成交时间", selection: $tradedAt)
                    TextField("数量", value: $quantity, format: .number)
                    TextField("成交价格", value: $price, format: .number)
                    TextField("费用", value: $fees, format: .number)
                    LabeledContent("成交币种", value: selectedHolding?.currency ?? "—")
                    TextField("1 成交币种 = 多少 \(baseCurrency)", value: $exchangeRateToBase, format: .number)
                    LabeledContent("折算成交额") {
                        Text(AppFormat.money(grossAmountInBase, currency: baseCurrency))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                }

                Section("对组合的影响") {
                    Toggle("同步更新该手动持仓的数量与成本", isOn: $applyToPosition)
                        .disabled(selectedHolding?.source != .manual)
                    Toggle("同时更新本地现金余额", isOn: $applyToCash)

                    if selectedHolding?.source == .longbridge {
                        Text("长桥持仓以券商同步结果为准，本地交易只作为决策账本，不会修改券商持仓。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("卖出会减少手动持仓；买入会按成交金额和费用重新计算平均成本。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("备注") {
                    TextField("交易理由、平台或其他说明", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppTheme.warning)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.negative)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("记录交易")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存记录") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 690)
        .onChange(of: selectedHoldingID) { _, _ in
            guard let selectedHolding else { return }
            price = selectedHolding.lastPrice
            exchangeRateToBase = selectedHolding.exchangeRateToBase
            applyToPosition = selectedHolding.source == .manual
            errorMessage = nil
        }
    }

    private var selectedHolding: Holding? {
        holdings.first { $0.id == selectedHoldingID }
    }

    private var grossAmountInBase: Double {
        max(0, quantity) * max(0, price) * max(0, exchangeRateToBase)
    }

    private var validationMessage: String? {
        guard let selectedHolding else { return "请先录入至少一项持仓。" }
        if side == .sell && applyToPosition && quantity > selectedHolding.shares {
            return "卖出数量超过当前手动持仓 \(AppFormat.quantity(selectedHolding.shares))。"
        }
        return nil
    }

    private var isValid: Bool {
        selectedHolding != nil && quantity.isFinite && price.isFinite && fees.isFinite &&
        exchangeRateToBase.isFinite && quantity > 0 && price >= 0 && fees >= 0 &&
        exchangeRateToBase > 0 && validationMessage == nil
    }

    private func save() {
        guard isValid, let selectedHolding else { return }
        let trade = RecordedTrade(
            id: UUID().uuidString,
            holdingID: selectedHolding.id,
            symbol: selectedHolding.symbol,
            name: selectedHolding.name,
            assetType: selectedHolding.assetType,
            side: side,
            quantity: quantity,
            price: price,
            fees: fees,
            currency: selectedHolding.currency,
            exchangeRateToBase: exchangeRateToBase,
            tradedAt: tradedAt,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: .now
        )

        if let error = onSave(trade, applyToPosition, applyToCash) {
            errorMessage = error
        } else {
            dismiss()
        }
    }
}
