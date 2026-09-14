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
                // As regioes laterais encostam na curvatura da ilha: sem margem,
                // o primeiro e o ultimo caractere saem cortados. Dai o padding.
                DynamicIslandExpandedRegion(.leading) {
                    if context.state.detailed {
                        ValueBlock(title: context.state.isWireless ? "na bobina" : "na tomada",
                                   value: Fmt.watts(context.state.watts),
                                   alignment: .leading)
                            .padding(.leading, 10)
                    } else {
                        LeanValue(text: Fmt.watts(context.state.watts),
                                  tint: StatusIcon.color(context.state))
                            .padding(.leading, 10)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.detailed {
                        ValueBlock(title: "na bateria",
                                   value: Fmt.watts(context.state.intoBatteryWatts),
                                   alignment: .trailing)
                            .padding(.trailing, 10)
                    } else {
                        LeanValue(text: Fmt.watts(context.state.intoBatteryWatts),
                                  tint: .secondary)
                            .padding(.trailing, 10)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if context.state.detailed {
                        CenterETA(state: context.state)
                    } else {
                        LeanCenter(state: context.state)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // No modo enxuto o rodape some inteiro: e ele que fazia a
                    // ilha virar um card de tres alturas.
                    if context.state.detailed {
                        BottomDetail(context: context)
                    }
                }
            } compactLeading: {
                HStack(spacing: 2) {
                    Image(systemName: StatusIcon.name(context.state))
                    Text(Fmt.wattsCompact(context.state.watts))
                        .monospacedDigit()
                }
                .foregroundStyle(context.isStale ? .secondary : StatusIcon.color(context.state))
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

/// Um numero e mais nada: uma linha de altura, sem legenda embaixo.
private struct LeanValue: View {
    let text: String
    var tint: Color = .primary
    var body: some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: true, vertical: false)
    }
}

/// Centro do modo enxuto: o nivel alinhado com as potencias dos lados, e a
/// temperatura logo abaixo em letra miuda — ocupando o vao estreito do centro
/// em vez de uma terceira faixa na largura toda.
private struct LeanCenter: View {
    let state: ChargeActivityAttributes.ContentState
    var body: some View {
        VStack(spacing: -1) {
            Text("\(state.percent)%")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .monospacedDigit()
            if let t = state.batteryTempC {
                Text(String(format: "%.1f°", t))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(state.throttling ? .orange : .secondary)
            } else if state.onHold {
                Text("em espera").font(.system(size: 10)).foregroundStyle(.orange)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

private struct CenterETA: View {
    let state: ChargeActivityAttributes.ContentState
    var body: some View {
        VStack(spacing: 0) {
            if state.onHold {
                Text("\(state.percent)%").font(.headline).monospacedDigit()
                Text("em espera").font(.caption2).foregroundStyle(.orange)
            } else if let eta = state.eta, let range = state.etaRange {
                // A hora prevista e o numero principal, igual ao "chega as 20:06".
                Text(eta, style: .time)
                    .font(.headline)
                    .monospacedDigit()
                // A contagem desce sozinha, sem nenhuma atualizacao nossa.
                HStack(spacing: 3) {
                    Text("faltam")
                    Text(timerInterval: range, countsDown: true).monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                Text("\(state.percent)%").font(.headline).monospacedDigit()
                Text("carregando").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }
}

/// Rodape da ilha expandida. Duas apresentacoes, escolhidas pelo atalho que
/// criou (ou atualizou) a atividade:
///
/// - **enxuta**: so uma linha fina de temperatura. A ilha fica quase da altura
///   da compacta, entao a aparicao automatica vira um pisca lateral em vez de um
///   card na sua cara.
/// - **completa**: barra de progresso, adaptador, perfil PD, temperatura e pico.
///
/// A linha de "medido / leituras" nao aparece em nenhuma das duas — ela vive so
/// no cartao da tela de bloqueio, onde ha espaco e voce consulta com calma.
private struct BottomDetail: View {
    let context: ActivityViewContext<ChargeActivityAttributes>

    var body: some View {
        if context.state.detailed {
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

                ThermalLine(state: context.state, showsPeak: true)
            }
        } else {
            ThermalLine(state: context.state, showsPeak: false)
        }
    }
}

/// Temperatura em destaque: e ela que decide quanta potencia o iOS deixa passar,
/// especialmente no sem fio dentro do bolso.
private struct ThermalLine: View {
    let state: ChargeActivityAttributes.ContentState
    var showsPeak: Bool = true
    var body: some View {
        HStack(spacing: 6) {
            if let t = state.batteryTempC {
                Label(String(format: "%.1f C", t), systemImage: "thermometer.medium")
                    .foregroundStyle(tint(t))
            }
            if showsPeak, let peak = state.peakWatts {
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

            LockScreenFooter(context: context)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

/// Rodape do cartao da tela de bloqueio.
///
/// A linha de "medido / leituras / continuo" saiu: ela existia para medir o
/// experimento do segundo plano, que ja foi respondido. Adaptador, temperatura e
/// pico foram fundidos numa linha so, e o perfil PD fica na outra ponta.
private struct LockScreenFooter: View {
    let context: ActivityViewContext<ChargeActivityAttributes>

    var body: some View {
        VStack(spacing: 7) {
            ProgressView(value: Double(min(context.state.percent, context.state.targetPercent)),
                         total: Double(context.state.targetPercent))
                .tint(context.state.onHold ? .orange : .green)

            HStack(spacing: 8) {
                Label(context.attributes.adapterName,
                      systemImage: context.state.isWireless ? "wave.3.right" : "cable.connector")

                if let t = context.state.batteryTempC {
                    Text("·").foregroundStyle(.tertiary)
                    Label(String(format: "%.1f °C", t), systemImage: "thermometer.medium")
                        .foregroundStyle(tempTint(t))
                }

                if let peak = context.state.peakWatts, peak > 0 {
                    Text("·").foregroundStyle(.tertiary)
                    Label(Fmt.watts(peak), systemImage: "arrow.up.right")
                }

                if context.state.throttling {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }

                Spacer(minLength: 6)

                if !context.attributes.negotiated.isEmpty {
                    Text(context.attributes.negotiated)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
    }

    private func tempTint(_ t: Double) -> Color {
        if t >= 40 { return .red }
        if t >= 37 { return .orange }
        return .secondary
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
        .fixedSize(horizontal: true, vertical: false)
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
