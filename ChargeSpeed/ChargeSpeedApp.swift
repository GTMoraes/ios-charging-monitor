import SwiftUI

@main
struct ChargeSpeedApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Tem que ser registrado antes do fim do launch.
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    LiveActivityController.shared.adopt()
                    // O prompt de localizacao so pode aparecer em primeiro plano.
                    // Autorizar liga o modo continuo; negar deixa o app igual ao
                    // que era, sem medicao com a tela apagada. Depois do "Ao usar"
                    // vem o pedido de "Sempre" (ver KeepAlive).
                    KeepAlive.shared.requestAuthorizationIfNeeded()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                LiveActivityController.shared.setAppActive(false)
                BackgroundRefresh.schedule()
                LiveActivityController.shared.beginBackgroundGrace()
            case .active:
                LiveActivityController.shared.setAppActive(true)
                LiveActivityController.shared.endBackgroundGrace()
                LiveActivityController.shared.adopt()
                KeepAlive.shared.requestAuthorizationIfNeeded()
                // Com o app em uso o iOS sempre deixa ligar a localizacao, ate com
                // "Ao usar". Religa aqui para o modo continuo valer quando sair.
                if LiveActivityController.shared.isRunning {
                    KeepAlive.shared.restart()
                }
            default:
                LiveActivityController.shared.setAppActive(false)
                LiveActivityController.shared.beginBackgroundGrace()
            }
        }
    }
}
