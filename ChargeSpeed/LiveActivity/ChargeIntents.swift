import AppIntents
import Foundation

/// Atalhos que resolvem o problema do gatilho.
///
/// O iOS nao acorda um app suspenso quando voce pluga o carregador. Mas os
/// Atalhos tem a automacao "Quando o iPhone for conectado ao carregador", e ela
/// pode rodar uma destas acoes. Com `openAppWhenRun = false` o app e acordado em
/// segundo plano, le os sensores e sobe a Live Activity sem abrir na sua cara.
struct StartChargeMonitorIntent: AppIntent {
    static var title: LocalizedStringResource = "Iniciar monitor de carga"
    static var description = IntentDescription("Le os sensores e mostra a Live Activity de carregamento.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        let monitor = PowerMonitor()
        monitor.refresh()
        LiveActivityController.shared.adopt()
        LiveActivityController.shared.noteBackgroundWake("atalho")
        LiveActivityController.shared.sync(monitor)
        BackgroundRefresh.schedule(after: 60)
        return .result()
    }
}

struct StopChargeMonitorIntent: AppIntent {
    static var title: LocalizedStringResource = "Parar monitor de carga"
    static var description = IntentDescription("Encerra a Live Activity de carregamento.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        LiveActivityController.shared.adopt()
        LiveActivityController.shared.endActivity()
        return .result()
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
