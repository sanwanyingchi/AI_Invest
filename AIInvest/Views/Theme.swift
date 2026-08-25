import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.12, green: 0.48, blue: 0.38)
    static let accentSoft = Color(red: 0.12, green: 0.48, blue: 0.38).opacity(0.12)
    static let positive = Color(red: 0.10, green: 0.55, blue: 0.36)
    static let negative = Color(red: 0.78, green: 0.25, blue: 0.24)
    static let warning = Color(red: 0.85, green: 0.55, blue: 0.12)
    static let info = Color(red: 0.20, green: 0.43, blue: 0.78)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            }
    }
}

extension View {
    func cardStyle(padding: CGFloat = 18) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

enum AppFormat {
    static func money(_ value: Double, currency: String = "HKD", decimals: Int = 0) -> String {
        let number = value.formatted(
            .number
                .grouping(.automatic)
                .precision(.fractionLength(decimals))
        )
        return "\(currency) \(number)"
    }

    static func number(_ value: Double, decimals: Int = 2) -> String {
        value.formatted(
            .number
                .grouping(.automatic)
                .precision(.fractionLength(decimals))
        )
    }

    static func quantity(_ value: Double) -> String {
        value.formatted(
            .number
                .grouping(.automatic)
                .precision(.fractionLength(0...8))
        )
    }

    static func percent(_ value: Double, signed: Bool = false, decimals: Int = 1) -> String {
        let prefix = signed && value > 0 ? "+" : ""
        return "\(prefix)\(value.formatted(.number.precision(.fractionLength(decimals))))%"
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(.dateTime.month().day().hour().minute())
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month().day())
    }
}

extension Color {
    static func performance(_ value: Double) -> Color {
        value >= 0 ? AppTheme.positive : AppTheme.negative
    }
}
