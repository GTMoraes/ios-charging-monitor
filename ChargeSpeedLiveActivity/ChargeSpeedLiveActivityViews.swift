import ActivityKit
import SwiftUI
import WidgetKit

struct ChargeSpeedLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChargeActivityAttributes.self) { context in
            LockScreenCard(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ValueBlock(title: context.state.isWireless ? "na bobina" : "na tomada",
                               value: Fmt.watts(context.state.watts),
                               alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ValueBlock(title: "na bateria",
                               value: Fmt.watts(context.state.intoBatteryWatts),
                               alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    CenterETA(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    BottomDetail(context: context)
                }
            } compactLeading: {
                HStack(spacing: 2) {
                    Image(systemName: StatusIcon.name(context.state))
                    Text(Fmt.wattsCompact(context.state.watts))
                        .monospacedDigit()
                }
                .foregroundStyle(StatusIcon.color(context.state))
            } compactTrailing: {
                CompactTrailing(state: context.state)
            } minimal: {
                Image(systemName: StatusIcon.name(context.state))
                    .foregroundStyle(StatusIcon.color(context.state))
            }
            .keylineTint(StatusIcon.color(context.state))
        }
    }
}

// MARK: - Pedacos

/// Lado direito compacto: a previsao, no mesmo espirito do "chega as 20:06".
/// O `style: .time` e desenhado pelo proprio iOS — nao depende de atualizacao nossa.
private struct CompactTrailing: View {
    let state: ChargeActivityAttributes.ContentState
    var body: some View {
        if state.showsETA, let eta = state.eta {
            Text(eta, style: .time)
                .monospacedDigit()
                .foregroundStyle(.green)
        } else {
            Text("\(state.percent)%")
                .monospacedDigit()
                .foregroundStyle(state.onHold ? .orange : .green)
        }
    }
}

private struct CenterETA: View {
    let state: ChargeActivityAttributes.ContentState
    var body: some View {
        VStack(spacing: 1) {
            if state.onHold {
                Text("em espera").font(.caption2).foregroundStyle(.orange)
                Text("\(state.percent)%").font(.headline).monospacedDigit()
            } else if let range = state.etaRange {
                // Contagem regressiva renderizada pelo sistema, sem atualizacao.
                Text(timerInterval: range, countsDown: true)
                    .font(.headline)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                Text("ate \(state.targetPercent)%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(state.percent)%").font(.headline).monospacedDigit()
                Text("carregando").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct BottomDetail: View {
    let context: ActivityViewContext<ChargeActivityAttributes>
    var body: some View {
        VStack(spacing: 5) {
            ProgressView(value: Double(min(context.state.percent, context.state.targetPercent)),
                         total: Double(context.state.targetPercent))
                .tint(context.state.onHold ? .orange : .green)

            HStack(spacing: 6) {
                Label(context.attributes.adapterName,
                      systemImage: context.state.isWireless ? "wave.3.right" : "cable.connector")
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !context.attributes.negotiated.isEmpty {
                    Text(context.attributes.negotiated).lineLimit(1)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            ThermalLine(state: context.state)
            FreshnessLine(context: context)
        }
    }
}

/// Temperatura em destaque: e ela que decide quanta potencia o iOS deixa passar,
/// especialmente no sem fio dentro do bolso.
private struct ThermalLine: View {
    let state: ChargeActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: 6) {
            if let t = state.batteryTempC {
                Label(String(format: "%.1f C", t), systemImage: "thermometer.medium")
                    .foregroundStyle(tint(t))
            }
            if let peak = state.peakWatts {
                Label(Fmt.watts(peak), systemImage: "arrow.up.right")
                    .foregroundStyle(.secondary)
            }
            if state.throttling {
                Label("potencia cortada", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .lineLimit(1)
    }

    private func tint(_ t: Double) -> Color {
        if t >= 40 { return .red }
        if t >= 37 { return .orange }
        return .secondary
    }
}

/// Quando os numeros foram medidos, e quando o iOS acordou o app pela ultima vez.
/// Esta linha e a medicao do experimento de segundo plano.
private struct FreshnessLine: View {
    let context: ActivityViewContext<ChargeActivityAttributes>
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: context.isStale ? "clock.badge.exclamationmark" : "clock")
            Text("medido ") + Text(context.state.measuredAt, style: .time)
            Text("· \(context.state.updateCount) leituras")
            if let wake = context.state.lastBackgroundWake,
               let kind = context.state.lastBackgroundKind {
                Text("· bg \(kind) ") + Text(wake, style: .time)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 10))
        .monospacedDigit()
        .foregroundStyle(context.isStale ? .orange : .secondary)
        .lineLimit(1)
    }
}

// MARK: - Tela de bloqueio

private struct LockScreenCard: View {
    let context: ActivityViewContext<ChargeActivityAttributes>
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: StatusIcon.name(context.state))
                    .foregroundStyle(StatusIcon.color(context.state))
                Text(Fmt.watts(context.state.watts))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(context.state.wattsLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    if context.state.showsETA, let eta = context.state.eta {
                        Text(eta, style: .time)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text("ate \(context.state.targetPercent)%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(context.state.percent)%")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text(context.state.onHold ? "em espera" : "carregando")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 14) {
                ValueBlock(title: "na bateria",
                           value: Fmt.watts(context.state.intoBatteryWatts),
                           alignment: .leading)
                if let v = context.state.inputVoltage {
                    ValueBlock(title: "entrada",
                               value: String(format: "%.2f V", v),
                               alignment: .leading)
                }
                if let a = context.state.inputCurrent, !context.state.isWireless {
                    ValueBlock(title: "corrente",
                               value: String(format: "%.2f A", a),
                               alignment: .leading)
                }
                Spacer(minLength: 0)
            }

            BottomDetail(context: context)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Utilitarios

private struct ValueBlock: View {
    let title: String
    let value: String
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }
}

private enum StatusIcon {
    static func name(_ s: ChargeActivityAttributes.ContentState) -> String {
        if s.onHold { return "pause.circle.fill" }
        if s.throttling { return "thermometer.high" }
        return s.isWireless ? "wave.3.right.circle.fill" : "bolt.fill"
    }
    static func color(_ s: ChargeActivityAttributes.ContentState) -> Color {
        if s.onHold { return .orange }
        if s.throttling { return .red }
        return .green
    }
}

private enum Fmt {
    static func watts(_ w: Double?) -> String {
        guard let w, w.isFinite else { return "--" }
        return String(format: w < 10 ? "%.2f W" : "%.1f W", w)
    }
    static func wattsCompact(_ w: Double) -> String {
        guard w.isFinite else { return "--" }
        return String(format: w < 10 ? "%.1f" : "%.0f", w) + "W"
    }
}
