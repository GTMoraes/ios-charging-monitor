import AppIntents
import Foundation

/// Acoes para os Atalhos.
///
/// **Por que `LiveActivityIntent` e nao `AppIntent`.** A Apple exige que o app
/// esteja em primeiro plano e visivel para criar uma Live Activity localmente:
/// chamada de background, `Activity.request` falha com
/// `ActivityAuthorizationError.visibility`. `LiveActivityIntent` e a excecao
/// oficial — quando a acao e disparada pelo usuario (Atalho, Siri, widget), o
/// sistema concede ao app o privilegio de criar a atividade mesmo em background.

/// Apresentacao **enxuta** — para as automacoes. A ilha expandida fica quase da
/// altura da compacta, entao a aparicao automatica vira um pisca lateral em vez
/// de um card na sua cara.
struct StartChargeMonitorIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Iniciar monitor de carga"
    static var description = IntentDescription("Mostra a Live Activity de carregamento com a ilha enxuta.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await ChargeMonitorStart.run(detailed: false)
    }
}

/// Apresentacao **completa** — para o Botao de Acao e o Centro de Controle,
/// quando e voce que pede. Se a atividade ja estiver rodando, ela apenas **troca
/// de layout sem recriar** — e recriar e o que faz a ilha expandir.
struct StartDetailedMonitorIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Iniciar monitor detalhado"
    static var description = IntentDescription("Ilha completa: barra, adaptador, perfil PD, temperatura e pico.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await ChargeMonitorStart.run(detailed: true)
    }
}

struct StopChargeMonitorIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Parar monitor de carga"
    static var description = IntentDescription("Encerra a Live Activity de carregamento.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        LiveActivityController.shared.adopt()
        let estava = LiveActivityController.shared.isRunning
        LiveActivityController.shared.endActivity()
        return .result(dialog: estava ? "Monitor encerrado." : "Nao havia monitor rodando.")
    }
}

/// Corpo comum das duas acoes de inicio.
@MainActor
private enum ChargeMonitorStart {
    static func run(detailed: Bool) async throws -> some IntentResult & ProvidesDialog {
        LiveActivityController.shared.detailedLayout = detailed

        let monitor = PowerMonitor()

        // Aquecimento. Nos primeiros segundos depois de plugar a corrente ainda
        // nao subiu: a leitura crua diz 0 W e "em espera". Duas tentativas so
        // pegam o caso facil; o resto o loop continuo corrige em segundos.
        var pluggedIn = false
        for _ in 0..<4 {
            monitor.refresh()
            guard let snap = monitor.snapshot else { break }
            pluggedIn = snap.externalConnected
            if !pluggedIn { break }
            if let watts = snap.primaryWatts?.value, watts > 0.5 { break }
            try? await Task.sleep(for: .milliseconds(500))
        }

        guard let snap = monitor.snapshot else {
            return .result(dialog: "Nao consegui ler os sensores.")
        }
        guard pluggedIn else {
            return .result(dialog: "O carregador nao esta conectado.")
        }

        LiveActivityController.shared.adopt()
        LiveActivityController.shared.noteBackgroundWake("atalho")
        LiveActivityController.shared.sync(monitor)

        // A primeira leitura de um processo recem-acordado costuma vir vazia: os
        // sensores HID ainda nao responderam. Em vez de esperar mais aqui (o
        // intent tem orcamento curto), entrega a atividade e deixa o loop
        // continuo corrigir. `takeOwnership` e o que mantem o monitor vivo
        // depois que este metodo retorna.
        LiveActivityController.shared.takeOwnership(of: monitor)
        if !LiveActivityController.shared.isMeasuring {
            LiveActivityController.shared.beginBackgroundGrace()
        }
        BackgroundRefresh.schedule(after: 60)

        if let failure = LiveActivityController.shared.lastFailure {
            return .result(dialog: "Nao consegui criar a Live Activity: \(failure)")
        }

        let watts = snap.primaryWatts.map { String(format: "%.1f W", $0.value) } ?? "sem leitura"
        let modo = detailed ? "detalhado" : "enxuto"
        return .result(dialog: "Monitorando: \(watts) — \(modo), \(KeepAlive.shared.statusText).")
    }
}

struct ChargeSpeedShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartChargeMonitorIntent(),
                    phrases: ["Iniciar o \(.applicationName)"],
                    shortTitle: "Iniciar monitor",
                    systemImageName: "bolt.fill")
        AppShortcut(intent: StartDetailedMonitorIntent(),
                    phrases: ["Monitor detalhado do \(.applicationName)"],
                    shortTitle: "Monitor detalhado",
                    systemImageName: "bolt.badge.checkmark")
        AppShortcut(intent: StopChargeMonitorIntent(),
                    phrases: ["Parar o \(.applicationName)"],
                    shortTitle: "Parar monitor",
                    systemImageName: "bolt.slash")
    }
}
