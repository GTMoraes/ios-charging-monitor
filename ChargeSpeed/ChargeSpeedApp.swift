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
            if phase == .background { BackgroundRefresh.schedule() }
        }
    }
}
