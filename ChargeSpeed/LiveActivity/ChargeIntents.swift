import AppIntents
import Foundation

/// Acoes para as automacoes dos Atalhos.
///
/// **Por que `LiveActivityIntent` e nao `AppIntent`.** A Apple exige que o app
/// esteja em primeiro plano e visivel para criar uma Live Activity localmente:
/// chamada de background, `Activity.request` falha com
/// `ActivityAuthorizationError.visibility`. `LiveActivityIntent` e a excecao
/// oficial — quando a acao e disparada pelo usuario (Atalho, Siri, widget), o
/// sistema concede ao app o privilegio de iniciar a atividade mesmo em background.
struct StartChargeMonitorIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Iniciar monitor de carga"
    static var description = IntentDescription("Mostra a Live Activity de carregamento.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let monitor = PowerMonitor()

        // Aquecimento. Nos primeiros segundos depois de plugar, a corrente ainda
        // nao subiu: a leitura crua diz 0 W e "em espera", e essa foto errada
        // ficaria congelada na Live Activity ate o app ser aberto de novo.
        // Espera a potencia aparecer de verdade antes de criar a atividade.
        var pluggedIn = false
        for _ in 0..<8 {
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
        BackgroundRefresh.schedule(after: 60)

        if let failure = LiveActivityController.shared.lastFailure {
            return .result(dialog: "Nao consegui criar a Live Activity: \(failure)")
        }
        let watts = snap.primaryWatts.map { String(format: "%.1f W", $0.value) } ?? "sem leitura"
        return .result(dialog: "Monitorando: \(watts) — \(KeepAlive.shared.statusText).")
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

struct ChargeSpeedShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartChargeMonitorIntent(),
                    phrases: ["Iniciar o \(.applicationName)"],
                    shortTitle: "Iniciar monitor",
                    systemImageName: "bolt.fill")
        AppShortcut(intent: StopChargeMonitorIntent(),
                    phrases: ["Parar o \(.applicationName)"],
                    shortTitle: "Parar monitor",
                    systemImageName: "bolt.slash")
    }
}
