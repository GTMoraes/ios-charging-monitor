import BackgroundTasks
import Foundation

/// O experimento do segundo plano.
///
/// Duas apostas, registradas juntas para medir qual o iOS honra:
///
/// - `BGAppRefreshTask`: a via classica. O iOS decide quando, aprendendo do seu
///   uso. Costuma ser espacada e imprevisivel.
/// - `BGProcessingTask` com `requiresExternalPower = true`: pede explicitamente
///   para rodar quando o aparelho esta na tomada. E exatamente a nossa situacao,
///   e por isso a aposta mais promissora — o iOS e bem mais generoso com tempo
///   de execucao quando o telefone esta carregando e parado.
///
/// A cada acordada, o horario e o mecanismo ficam registrados e aparecem na
/// Live Activity expandida. Depois de uma noite na tomada da para ler ali
/// quantas vezes o iOS realmente deixou o app rodar.
enum BackgroundRefresh {

    /// Derivados do bundle id em tempo de execucao, para acompanhar a troca de
    /// bundle que o workflow faz. Tem que casar com BGTaskSchedulerPermittedIdentifiers.
    static var refreshID: String { base + ".refresh" }
    static var processingID: String { base + ".processing" }
    private static var base: String { Bundle.main.bundleIdentifier ?? "com.gregwilson.chargespeed" }

    /// Precisa acontecer antes do fim do launch — chamado do init do App.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshID, using: nil) { task in
            handle(task, kind: "refresh")
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: processingID, using: nil) { task in
            handle(task, kind: "tomada")
        }
    }

    static func schedule(after seconds: TimeInterval = 5 * 60) {
        let refresh = BGAppRefreshTaskRequest(identifier: refreshID)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: seconds)
        try? BGTaskScheduler.shared.submit(refresh)

        let processing = BGProcessingTaskRequest(identifier: processingID)
        processing.requiresExternalPower = true
        processing.requiresNetworkConnectivity = false
        processing.earliestBeginDate = Date(timeIntervalSinceNow: seconds)
        try? BGTaskScheduler.shared.submit(processing)
    }

    private static func handle(_ task: BGTask, kind: String) {
        // Reagenda primeiro: se o trabalho falhar, a corrente nao se perde.
        schedule()

        let work = Task { @MainActor in
            let monitor = PowerMonitor()
            monitor.refresh()
            LiveActivityController.shared.adopt()
            LiveActivityController.shared.noteBackgroundWake(kind)
            LiveActivityController.shared.sync(monitor)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}
