import ActivityKit
import Foundation

/// Cria, atualiza e encerra a Live Activity de carregamento.
///
/// Estrategia: o que e estatico na sessao (adaptador, perfil PD negociado) vai
/// nos `attributes` e nunca precisa de atualizacao. O que muda devagar (nivel,
/// previsao) vira uma data, e o proprio iOS anda com a contagem sem nos consultar.
/// So os watts instantaneos dependem de o app ganhar tempo de execucao.
@MainActor
final class LiveActivityController {

    static let shared = LiveActivityController()
    private init() {}

    /// Alvo da previsao. 80% porque e onde a curva de carga vira e onde a
    /// maioria dos limites de carga do iOS segura.
    static let targetPercent = 80
    /// Intervalo minimo entre atualizacoes, para nao gastar a cota do sistema.
    private static let minInterval: TimeInterval = 4

    private var activity: Activity<ChargeActivityAttributes>?
    private var currentAttributes: ChargeActivityAttributes?
    private var lastState: ChargeActivityAttributes.ContentState?
    private var lastPush: Date = .distantPast
    private var updateCount = 0

    /// A previsao e recalculada apenas quando o nivel muda, senao a contagem
    /// ficaria tremendo a cada leitura.
    private var anchorPercent: Int?
    private var anchorETA: Date?
    private var anchorStart: Date?

    private(set) var lastBackgroundWake: Date?
    private(set) var lastBackgroundKind: String?

    /// Referencia ao monitor que esta alimentando a atividade, para continuar
    /// medindo nos segundos de graca depois que o app sai de cena.
    private weak var monitorRef: PowerMonitor?
    private var graceTask: Task<Void, Never>?
    /// Quanto tempo os numeros valem antes do iOS marcar como velhos.
    private var staleWindow: TimeInterval = 600

    var isRunning: Bool { activity != nil }

    /// Reassume uma atividade que ja estava rodando (app relancado, ou acordado
    /// em segundo plano num processo novo).
    func adopt() {
        if activity == nil {
            activity = Activity<ChargeActivityAttributes>.activities.first
            currentAttributes = activity?.attributes
        }
    }

    /// Registra que o iOS nos deu tempo de execucao em segundo plano.
    /// E a medicao do experimento — aparece na Live Activity expandida.
    func noteBackgroundWake(_ kind: String) {
        lastBackgroundWake = .now
        lastBackgroundKind = kind
    }

    /// Ponto de entrada unico. Chamado a cada leitura do PowerMonitor.
    func sync(_ monitor: PowerMonitor) {
        monitorRef = monitor
        guard let snap = monitor.snapshot else { return }

        guard snap.externalConnected else {
            endActivity()
            return
        }

        let attributes = makeAttributes(snap)
        let state = makeState(snap, monitor: monitor)

        // Trocou de carregador no meio: a parte estatica mudou, recomeca.
        if let current = currentAttributes, current != attributes {
            endActivity()
        }

        if let activity {
            guard shouldPush(state) else { return }
            let content = ActivityContent(state: state,
                                          staleDate: state.measuredAt.addingTimeInterval(staleWindow))
            Task { await activity.update(content) }
            lastPush = .now
            lastState = state
        } else {
            start(attributes: attributes, state: state)
        }
    }

    /// Chamado quando o app sai de cena. O iOS concede uns 30 segundos antes de
    /// suspender o processo: aproveitamos para continuar medindo. Serve sobretudo
    /// para pegar o desplugue quando ele acontece logo depois de bloquear a tela.
    func beginBackgroundGrace() {
        guard isRunning, let monitor = monitorRef else { return }
        graceTask?.cancel()
        staleWindow = 180
        graceTask = Task { @MainActor in
            let deadline = Date.now.addingTimeInterval(25)
            while !Task.isCancelled, Date.now < deadline {
                monitor.refresh()
                if monitor.snapshot?.externalConnected == false { return }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func endBackgroundGrace() {
        graceTask?.cancel()
        graceTask = nil
        staleWindow = 600
    }

    func endActivity() {
        graceTask?.cancel()
        graceTask = nil
        let finishing = activity
        activity = nil
        currentAttributes = nil
        anchorPercent = nil
        anchorETA = nil
        anchorStart = nil
        updateCount = 0
        let final = lastState
        lastState = nil
        guard let finishing else { return }
        Task {
            let content = final.map { ActivityContent(state: $0, staleDate: nil) }
            await finishing.end(content, dismissalPolicy: .immediate)
        }
    }

    // MARK: - Interno

    private func start(attributes: ChargeActivityAttributes,
                       state: ChargeActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state,
                                         staleDate: state.measuredAt.addingTimeInterval(staleWindow)),
                pushType: nil)
            currentAttributes = attributes
            lastState = state
            lastPush = .now
        } catch {
            activity = nil
            currentAttributes = nil
        }
    }

    /// Atualiza no ritmo minimo, ou imediatamente quando algo relevante muda.
    private func shouldPush(_ state: ChargeActivityAttributes.ContentState) -> Bool {
        guard let last = lastState else { return true }
        if state.percent != last.percent { return true }
        if state.onHold != last.onHold { return true }
        if state.eta != last.eta { return true }
        if state.throttling != last.throttling { return true }
        if state.lastBackgroundWake != last.lastBackgroundWake { return true }
        return Date.now.timeIntervalSince(lastPush) >= Self.minInterval
    }

    private func makeAttributes(_ snap: PowerSnapshot) -> ChargeActivityAttributes {
        let name = snap.adapterName
            ?? snap.adapterDescription
            ?? (snap.isWirelessInput ? "sem fio" : "carregador")
        return ChargeActivityAttributes(adapterName: name, negotiated: negotiatedText(snap))
    }

    private func negotiatedText(_ snap: PowerSnapshot) -> String {
        if let n = snap.adapterNegotiated {
            let v = Double(n.voltage_mV) / 1000
            let a = Double(n.current_mA) / 1000
            return String(format: "%.1f V x %.2f A = %.0f W", v, a, v * a)
        }
        if let w = snap.adapterWatts { return "\(w) W" }
        return ""
    }

    private func makeState(_ snap: PowerSnapshot,
                           monitor: PowerMonitor) -> ChargeActivityAttributes.ContentState {
        updateCount += 1
        let percent = snap.percent ?? 0
        let into = snap.batteryWatts
        let primary = snap.primaryWatts

        if anchorPercent != percent {
            anchorPercent = percent
            anchorStart = .now
            if snap.isChargingOnHold || percent >= Self.targetPercent {
                anchorETA = nil
            } else {
                // A previsao usa os watts que chegam na BATERIA, nao os da tomada:
                // o consumo do aparelho nao carrega a bateria.
                let watts = into ?? primary?.value ?? 0
                anchorETA = ChargeETA.estimate(from: percent,
                                               to: Self.targetPercent,
                                               measuredWatts: watts,
                                               batteryWattHours: monitor.batteryWattHours)
            }
        }

        return ChargeActivityAttributes.ContentState(
            watts: primary?.value ?? 0,
            wattsLabel: primary?.label ?? "",
            intoBatteryWatts: into,
            percent: percent,
            targetPercent: Self.targetPercent,
            eta: anchorETA,
            etaStart: anchorStart ?? .now,
            onHold: snap.isChargingOnHold,
            isWireless: snap.isWirelessInput,
            inputVoltage: snap.isWirelessInput ? snap.wirelessInputVoltage : snap.usbInputVoltage,
            inputCurrent: snap.usbInputCurrent,
            batteryTempC: snap.batteryTemperatureC,
            peakWatts: monitor.peak?.watts,
            throttling: monitor.isThrottling,
            measuredAt: snap.date,
            updateCount: updateCount,
            lastBackgroundWake: lastBackgroundWake,
            lastBackgroundKind: lastBackgroundKind)
    }
}
