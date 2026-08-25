import SwiftUI

struct PageHeader<Trailing: View>: View {
    let eyebrow: String?
    let title: String
    let subtitle: String
    let trailing: () -> Trailing

    init(
        eyebrow: String? = nil,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 7) {
                if let eyebrow {
                    Text(eyebrow.uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(AppTheme.accent)
                }

                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)
            trailing()
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(eyebrow: String? = nil, title: String, subtitle: String) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    var tint: Color = AppTheme.accent
    var systemImage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

struct StatusPill: View {
    let text: String
    let tint: Color
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
            }
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

struct SectionTitle: View {
    let title: String
    let subtitle: String?
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.link)
            }
        }
    }
}

struct SimulationBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "testtube.2")
                .foregroundStyle(AppTheme.info)
            Text("长桥数据当前为模拟模式")
                .font(.subheadline.weight(.semibold))
            Text("手动录入的数据保存在本机，并会参与组合计算。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.info.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct LiveDataBanner: View {
    let syncState: SyncState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }

    private var title: String {
        switch syncState {
        case .failed: "长桥同步失败"
        case .syncing: "正在同步长桥"
        case .idle, .success: "长桥只读数据"
        }
    }

    private var detail: String {
        switch syncState {
        case .failed(let message): "继续显示上一次本地缓存 · \(message)"
        case .syncing: "正在更新账户余额、持仓和行情。"
        case .success(let date): "最近同步 \(AppFormat.dateTime(date)) · 不支持下单。"
        case .idle: "等待首次同步 · 不支持下单。"
        }
    }

    private var tint: Color {
        if case .failed = syncState { return AppTheme.negative }
        return AppTheme.positive
    }

    private var systemImage: String {
        switch syncState {
        case .failed: "exclamationmark.triangle.fill"
        case .syncing: "arrow.triangle.2.circlepath"
        case .idle, .success: "lock.shield.fill"
        }
    }
}

struct CodexGenerationBanner: View {
    let message: String
    let isRunning: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "sparkles")
                    .foregroundStyle(AppTheme.info)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(isRunning ? "Codex 正在分析" : "Codex 生成结果")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(AppTheme.info.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct EvidenceRow: View {
    let text: String
    var positive: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: positive ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(positive ? AppTheme.positive : AppTheme.warning)
                .font(.caption)
                .padding(.top, 2)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
