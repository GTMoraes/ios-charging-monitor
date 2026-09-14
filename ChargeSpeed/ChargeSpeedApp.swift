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
                    // que era, sem medicao com a tela apagada.
                    KeepAlive.shared.requestAuthorizationIfNeeded()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                BackgroundRefresh.schedule()
                LiveActivityController.shared.beginBackgroundGrace()
            case .active:
                LiveActivityController.shared.endBackgroundGrace()
                LiveActivityController.shared.adopt()
                KeepAlive.shared.requestAuthorizationIfNeeded()
            default:
                LiveActivityController.shared.beginBackgroundGrace()
            }
        }
    }
}
