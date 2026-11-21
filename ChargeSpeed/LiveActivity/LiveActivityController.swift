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
    /// Desde quando a leitura crua diz "em espera". Logo depois de plugar ela
    /// diz isso por alguns segundos, antes da corrente subir — reportar na hora
    /// deixaria a Live Activity travada num "em espera / 0.0 W" que e mentira.
    private var holdSince: Date?

    private var anchorPercent: Int?
    private var anchorETA: Date?
    private var anchorStart: Date?

    private(set) var lastBackgroundWake: Date?
    private(set) var lastBackgroundKind: String?
    /// Motivo da ultima falha ao criar a atividade. `visibility` significa que o
    /// app tentou criar em background sem o privilegio de LiveActivityIntent.
    private(set) var lastFailure: String?

    /// Referencia ao monitor que esta alimentando a atividade, para continuar
    /// medindo nos segundos de graca depois que o app sai de cena.
    private weak var monitorRef: PowerMonitor?
    /// Monitor proprio, para quando o app e acordado sem interface (pelo Atalho).
    /// Sem isto o monitor local do intent seria desalocado no `return` e o loop
    /// de medicao morreria antes da primeira leitura boa. Liberado assim que o
    /// app volta ao primeiro plano, para nao coexistir com o do ContentView.
    private var ownedMonitor: PowerMonitor?
    /// Apresentacao escolhida pelo atalho que chamou. Persistida para o app
    /// manter a escolha entre relancamentos.
    var detailedLayout: Bool {
        get { UserDefaults.standard.bool(forKey: "detailedLayout") }
        set { UserDefaults.standard.set(newValue, forKey: "detailedLayout") }
    }

    /// Verdadeiro quando o app tem interface ativa. Nesse caso o monitor do
    /// ContentView ja esta medindo, e o intent nao deve criar um segundo — dois
    /// monitores gravariam o mesmo pico e a mesma sessao no UserDefaults.
    private var appIsActive = false
    /// Leituras seguidas dizendo "desconectado". Uma leitura ruim isolada nao
    /// pode encerrar a atividade.
    private var disconnectedStreak = 0
    private var graceTask: Task<Void, Never>?
    /// Quanto tempo os numeros valem antes do iOS marcar como velhos.
    private var staleWindow: TimeInterval = 600

    var isRunning: Bool { activity != nil }

    /// Verdadeiro enquanto um atalho esta rodando. So nesse momento, ou com o app
    /// aberto, o iOS deixa criar a atividade; fora disso `Activity.request` falha
    /// com `visibility`, e nao adianta tentar.
    private var intentRunning = false
    /// A pessoa dispensou a atividade na tela de bloqueio. Com o app aberto ela
    /// nao e recriada sozinha; volta quando um atalho pedir ou depois de desplugar.
    private var userDismissed = false
    /// O iOS encerra qualquer Live Activity depois de 8 h. Um atalho que rode
    /// depois de 7 h troca por uma nova antes disso.
    private static let renewAfter: TimeInterval = 7 * 3600

    func beginIntent() {
        intentRunning = true
        userDismissed = false
        // Falha de um atalho anterior nao vale para este.
        lastFailure = nil
    }

    func endIntent() {
        intentRunning = false
    }

    /// Reassume uma atividade que ja estava rodando (app relancado, ou acordado
    /// em segundo plano num processo novo).
    /// Assume a posse do monitor criado pelo intent, para o loop continuar
    /// rodando depois que `perform()` retorna. Ignorado quando o app esta em
    /// primeiro plano: ali quem manda e o monitor do ContentView.
    func takeOwnership(of monitor: PowerMonitor) {
        guard !appIsActive else { return }
        ownedMonitor = monitor
        monitorRef = monitor
    }

    /// O monitor que ja esta medindo neste processo, se houver. Atalho e segundo
    /// plano reaproveitam ele em vez de criar outro: cada PowerMonitor novo abria
    /// mais um cliente HID, e o upstream documenta que o segundo cliente do mesmo
    /// processo le NaN.
    func reusableMonitor() -> PowerMonitor? { ownedMonitor ?? monitorRef }

    /// Chamado pelas transicoes de cena do app.
    func setAppActive(_ active: Bool) {
        appIsActive = active
        if active { ownedMonitor = nil }
    }

    /// Verdadeiro quando ha um loop de medicao de fundo rodando agora.
    var isMeasuring: Bool { graceTask != nil }

    /// Reassume a atividade que ja esta na tela. Precisa rodar antes de qualquer
    /// criacao: num processo novo (app morto e acordado pelo atalho) a variavel
    /// comeca vazia, e sem isto o app criava uma segunda atividade e a antiga
    /// ficava congelada na tela de bloqueio. Se houver mais de uma, encerra as
    /// sobras.
    func adopt() {
        dropIfFinished()
        guard activity == nil else { return }
        let alive = Activity<ChargeActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
        guard let first = alive.first else { return }
        activity = first
        currentAttributes = first.attributes
        if UserDefaults.standard.object(forKey: Self.startKey(first.id)) == nil {
            // Atividade criada por uma versao antiga, sem data: conta a partir de agora.
            UserDefaults.standard.set(Date.now, forKey: Self.startKey(first.id))
        }
        for extra in alive.dropFirst() {
            Task { await extra.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Troca a atividade por uma nova quando ela passou de 7 h. So funciona
    /// dentro de um atalho, que e quando o iOS deixa criar.
    func renewIfOld() {
        guard intentRunning, let activity,
              let started = UserDefaults.standard.object(forKey: Self.startKey(activity.id)) as? Date,
              Date.now.timeIntervalSince(started) > Self.renewAfter else { return }
        endActivity()
    }

    private static func startKey(_ id: String) -> String { "activityStart." + id }

    /// O iOS encerra a atividade sozinho depois de 8 h, e a pessoa pode
    /// dispensar na tela de bloqueio. Nos dois casos a referencia guardada
    /// continuava apontando para uma atividade morta: as atualizacoes caiam no
    /// vazio e nada a recriava enquanto o processo vivesse.
    private func dropIfFinished() {
        guard let activity else { return }
        switch activity.activityState {
        case .ended, .dismissed:
            if activity.activityState == .dismissed { userDismissed = true }
            UserDefaults.standard.removeObject(forKey: Self.startKey(activity.id))
            resetSession()
        default:
            break
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
        dropIfFinished()
        guard let snap = monitor.snapshot else { return }

        guard snap.externalConnected else {
            disconnectedStreak += 1
            if disconnectedStreak >= 3 { endActivity() }
            return
        }
        disconnectedStreak = 0
        if activity == nil { adopt() }

        let attributes = makeAttributes(snap)
        let state = makeState(snap, monitor: monitor)

        // A parte estatica mudou. Pode ser troca de carregador de verdade, ou so
        // uma leitura do adaptador que veio vazia ou incompleta (acontece logo
        // depois de o processo acordar, que e justamente quando o atalho roda).
        // Encerrar aqui com o app em segundo plano mata a atividade sem volta:
        // recriar fora do primeiro plano falha por `visibility`. Por isso so
        // recomeca com o app aberto e o adaptador lido de verdade; fora disso a
        // atividade que existe continua, com o nome antigo do adaptador.
        if let current = currentAttributes, current != attributes {
            let adapterKnown = snap.adapterName != nil || snap.adapterDescription != nil
            if appIsActive && adapterKnown {
                endActivity()
            }
        }

        if let activity {
            guard shouldPush(state) else { return }
            let content = ActivityContent(state: state,
                                          staleDate: state.measuredAt.addingTimeInterval(staleWindow))
            Task { await activity.update(content) }
            lastPush = .now
            lastState = state
        } else if intentRunning || (appIsActive && !userDismissed) {
            start(attributes: attributes, state: state)
        }
    }

    /// Chamado quando o app sai de cena.
    ///
    /// Sem monitor continuo: o iOS concede uns 30 segundos antes de suspender o
    /// processo, e o loop para ai. Serve para pegar o desplugue imediato.
    ///
    /// Com monitor continuo: o loop segue enquanto o carregador estiver ligado,
    /// numa **cadencia adaptativa** — o que economiza muito mais bateria do que
    /// reduzir a leitura para um valor fixo, porque o caro em iOS e acordar a CPU,
    /// nao o trabalho de cada leitura:
    ///
    /// - algo mudou (potencia variou mais de 1 W, mudou o nivel, mudou o estado
    ///   termico): **5 s**, para nao perder o transiente
    /// - regime normal: **10 s**
    /// - tres leituras seguidas praticamente iguais: **30 s**
    ///
    /// Numa carga monotona ele passa a maior parte do tempo em 30 s, ou seja,
    /// ~3% do trabalho que fazia a 1 Hz.
    func beginBackgroundGrace() {
        guard isRunning, let monitor = monitorRef else { return }
        graceTask?.cancel()
        staleWindow = 180
        // `restart`, e nao `start`: se o modo continuo foi ligado num momento em
        // que o iOS nao deixou (localizacao "Ao usar" com o app em segundo
        // plano), esta e a chance de religar.
        KeepAlive.shared.restart()

        graceTask = Task { @MainActor in
            let graceDeadline = Date.now.addingTimeInterval(25)
            var lastWatts: Double?
            var lastPercent: Int?
            var lastThrottling: Bool?
            var calmStreak = 0

            while !Task.isCancelled {
                monitor.refresh()
                guard let snap = monitor.snapshot else { return }

                if !snap.externalConnected {
                    // Confirma em ritmo rapido antes de encerrar: uma leitura
                    // ruim isolada nao pode derrubar a Live Activity.
                    disconnectedStreak += 1
                    if disconnectedStreak >= 3 {
                        KeepAlive.shared.stop()
                        endActivity()
                        return
                    }
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
                disconnectedStreak = 0

                // Sem monitor continuo, so a janela de cortesia do sistema.
                if !KeepAlive.shared.isActive, Date.now > graceDeadline { return }

                let watts = snap.primaryWatts?.value
                let throttling = monitor.isThermalStateHigh
                var moved = false
                if let watts, let lastWatts, abs(watts - lastWatts) > 1.0 { moved = true }
                if snap.percent != lastPercent { moved = true }
                if throttling != lastThrottling { moved = true }
                if let watts, let lastWatts, abs(watts - lastWatts) < 0.3 {
                    calmStreak += 1
                } else {
                    calmStreak = 0
                }
                lastWatts = watts
                lastPercent = snap.percent
                lastThrottling = throttling

                let interval: Duration
                if moved {
                    interval = .seconds(5)
                    calmStreak = 0
                } else if calmStreak >= 3 {
                    interval = .seconds(30)
                } else {
                    interval = .seconds(10)
                }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func endBackgroundGrace() {
        graceTask?.cancel()
        graceTask = nil
        staleWindow = 600
        // O monitor do ContentView reassume daqui em diante.
        ownedMonitor = nil
    }

    func endActivity() {
        let finishing = activity
        let final = lastState
        resetSession()
        userDismissed = false
        guard let finishing else { return }
        UserDefaults.standard.removeObject(forKey: Self.startKey(finishing.id))
        Task {
            let content = final.map { ActivityContent(state: $0, staleDate: nil) }
            await finishing.end(content, dismissalPolicy: .immediate)
        }
    }

    // MARK: - Interno

    private func resetSession() {
        graceTask?.cancel()
        graceTask = nil
        KeepAlive.shared.stop()
        activity = nil
        currentAttributes = nil
        anchorPercent = nil
        anchorETA = nil
        anchorStart = nil
        holdSince = nil
        disconnectedStreak = 0
        ownedMonitor = nil
        updateCount = 0
        lastState = nil
    }

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
            if let activity {
                UserDefaults.standard.set(Date.now, forKey: Self.startKey(activity.id))
            }
            KeepAlive.shared.start()
            lastFailure = nil
        } catch {
            activity = nil
            currentAttributes = nil
            lastFailure = String(describing: error)
        }
    }

    /// Atualiza no ritmo minimo, ou imediatamente quando algo relevante muda.
    private func shouldPush(_ state: ChargeActivityAttributes.ContentState) -> Bool {
        guard let last = lastState else { return true }
        if state.percent != last.percent { return true }
        if state.onHold != last.onHold { return true }
        if state.eta != last.eta { return true }
        if state.throttling != last.throttling { return true }
        if state.detailed != last.detailed { return true }
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

        // "Em espera" so vale depois de 45 s consistentes, o mesmo criterio que o
        // PowerMonitor usa para registrar um hold de verdade.
        if snap.isChargingOnHold {
            if holdSince == nil { holdSince = snap.date }
        } else {
            holdSince = nil
        }
        let settledHold = holdSince.map { snap.date.timeIntervalSince($0) >= 45 } ?? false
        let into = snap.batteryWatts
        let primary = snap.primaryWatts

        if anchorPercent != percent {
            anchorPercent = percent
            anchorStart = .now
            if settledHold || percent >= Self.targetPercent {
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
            onHold: settledHold,
            isWireless: snap.isWirelessInput,
            inputVoltage: snap.isWirelessInput ? snap.wirelessInputVoltage : snap.usbInputVoltage,
            inputCurrent: snap.usbInputCurrent,
            batteryTempC: snap.batteryTemperatureC,
            peakWatts: monitor.peak?.watts,
            throttling: monitor.isThermalStateHigh,
            continuous: KeepAlive.shared.isActive,
            detailed: detailedLayout,
            measuredAt: snap.date,
            updateCount: updateCount,
            lastBackgroundWake: lastBackgroundWake,
            lastBackgroundKind: lastBackgroundKind)
    }
}
