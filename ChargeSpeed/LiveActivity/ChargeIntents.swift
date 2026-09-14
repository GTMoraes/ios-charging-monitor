import AppIntents
import Foundation

/// Acoes para as automacoes dos Atalhos.
///
/// **Por que `LiveActivityIntent` e nao `AppIntent`.** A Apple exige que o app
/// esteja em primeiro plano e visivel para criar uma Live Activity localmente:
/// chamada de background, `Activity.request` falha com
/// `ActivityAuthorizationError.visibility`. Um `AppIntent` comum acordado pelos
/// Atalhos cai exatamente nesse caso — o app roda, le os sensores, tenta criar a
/// atividade e leva o erro na cara, calado.
///
/// `LiveActivityIntent` e a excecao oficial: quando a acao e disparada pelo
/// usuario (Atalho, Siri, widget interativo), o sistema concede ao app o
/// privilegio de iniciar e gerenciar Live Activities mesmo em background.

/// Modo economico: a Live Activity sobe, a previsao anda sozinha, mas os watts
/// so sao atualizados quando o app esta aberto.
struct StartChargeMonitorIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Iniciar monitor de carga"
    static var description = IntentDescription("Mostra a Live Activity de carregamento. Os watts atualizam quando o app esta aberto.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await ChargeMonitorStart.run(continuous: false)
    }
}

/// Modo continuo: mantem o app medindo com a tela apagada, enquanto o carregador
/// estiver conectado. Precisa da permissao de localizacao — veja `KeepAlive`.
struct StartContinuousMonitorIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Iniciar monitor continuo"
    static var description = IntentDescription("Mantem o app medindo com a tela apagada enquanto o carregador estiver conectado.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await ChargeMonitorStart.run(continuous: true)
    }
}

struct StopChargeMonitorIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Parar monitor de carga"
    static var description = IntentDescription("Encerra a Live Activity e desliga o monitor continuo.")

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
    static func run(continuous: Bool) async throws -> some IntentResult & ProvidesDialog {
        if continuous { KeepAlive.isEnabled = true }

        let monitor = PowerMonitor()
        monitor.refresh()

        guard let snap = monitor.snapshot else {
            return .result(dialog: "Nao consegui ler os sensores.")
        }
        guard snap.externalConnected else {
            return .result(dialog: "O carregador nao esta conectado.")
        }

        LiveActivityController.shared.adopt()
        LiveActivityController.shared.noteBackgroundWake("atalho")
        LiveActivityController.shared.sync(monitor)
        BackgroundRefresh.schedule(after: 60)

        // Rode a acao manualmente no app Atalhos para ver esta resposta — e o
        // unico diagnostico visivel quando algo falha em background.
        if let failure = LiveActivityController.shared.lastFailure {
            return .result(dialog: "Nao consegui criar a Live Activity: \(failure)")
        }

        let watts = snap.primaryWatts.map { String(format: "%.1f W", $0.value) } ?? "sem leitura"
        if continuous {
            return .result(dialog: "Monitorando: \(watts) — \(KeepAlive.shared.statusText).")
        }
        return .result(dialog: "Monitorando: \(watts).")
    }
}

struct ChargeSpeedShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartContinuousMonitorIntent(),
                    phrases: ["Iniciar o \(.applicationName)"],
                    shortTitle: "Monitor continuo",
                    systemImageName: "bolt.fill")
        AppShortcut(intent: StartChargeMonitorIntent(),
                    phrases: ["Monitor economico do \(.applicationName)"],
                    shortTitle: "Monitor economico",
                    systemImageName: "bolt.badge.clock")
        AppShortcut(intent: StopChargeMonitorIntent(),
                    phrases: ["Parar o \(.applicationName)"],
                    shortTitle: "Parar monitor",
                    systemImageName: "bolt.slash")
    }
}
