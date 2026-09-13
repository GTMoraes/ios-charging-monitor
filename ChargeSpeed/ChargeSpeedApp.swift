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
                .onAppear { LiveActivityController.shared.adopt() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                BackgroundRefresh.schedule()
                LiveActivityController.shared.beginBackgroundGrace()
            case .active:
                LiveActivityController.shared.endBackgroundGrace()
                LiveActivityController.shared.adopt()
            default:
                LiveActivityController.shared.beginBackgroundGrace()
            }
        }
    }
}
