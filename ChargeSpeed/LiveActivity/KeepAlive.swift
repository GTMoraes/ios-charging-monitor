import CoreLocation
import Foundation

/// Mantem o app executando enquanto o carregador esta conectado, para a Live
/// Activity continuar medindo com a tela apagada.
///
/// O iOS nao tem um modo de background para "monitorar a propria bateria". O que
/// existe e o modo de localizacao: com atualizacoes de localizacao ativas, o
/// processo nao e suspenso. E gambiarra, e vale dizer com clareza o que ela faz:
///
/// - O app **nao usa** a sua localizacao para nada. As coordenadas chegam no
///   delegate e sao descartadas na hora. Nada e lido, guardado ou enviado.
/// - A precisao pedida e a mais grosseira que o sistema oferece (3 km) e o filtro
///   de distancia e de 10 km, entao **o GPS nao liga**. O custo fica na ordem de
///   manter o processo residente, nao de rastrear posicao.
/// - Fica ativo **somente enquanto o carregador esta conectado**. Ao desplugar,
///   desliga junto com a Live Activity. Ou seja: o consumo sai da tomada, nao da
///   bateria — e a seta de localizacao na barra de status tambem some.
/// - Basta a permissao **"Ao Usar o App"**. O modo de background declarado no
///   Info.plist e o que permite continuar durante o carregamento; nao e preciso
///   pedir "Sempre".
@MainActor
final class KeepAlive: NSObject {

    static let shared = KeepAlive()

    private let manager = CLLocationManager()
    private(set) var isActive = false

    private static let enabledKey = "keepAliveEnabled"

    /// Preferencia do usuario. Ligada pela acao "Iniciar monitor continuo" dos
    /// Atalhos; desligada pela acao "Parar monitor de carga".
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    var authorization: CLAuthorizationStatus { manager.authorizationStatus }
    var isAuthorized: Bool {
        authorization == .authorizedAlways || authorization == .authorizedWhenInUse
    }

    /// Texto curto de status, para as acoes dos Atalhos responderem algo util.
    var statusText: String {
        if !Self.isEnabled { return "monitor continuo desligado" }
        switch authorization {
        case .notDetermined: return "falta autorizar a localizacao — abra o app uma vez"
        case .denied, .restricted: return "localizacao negada em Ajustes"
        default: return isActive ? "monitor continuo ativo" : "monitor continuo pronto"
        }
    }

    private override init() {
        super.init()
        manager.delegate = self
        // O mais barato que da: sem GPS, praticamente sem relatorios.
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = 10_000
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .other
    }

    /// So funciona com o app em primeiro plano — por isso o fluxo pede para
    /// abrir o app uma vez depois de ligar o monitor continuo.
    func requestAuthorizationIfNeeded() {
        guard Self.isEnabled, authorization == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        guard Self.isEnabled, isAuthorized, !isActive else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        isActive = true
    }

    func stop() {
        guard isActive else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isActive = false
    }
}

extension KeepAlive: CLLocationManagerDelegate {
    /// As coordenadas sao descartadas de proposito. O interesse e apenas no
    /// efeito colateral de manter o processo vivo.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if isAuthorized, LiveActivityController.shared.isRunning {
            start()
        } else if !isAuthorized {
            stop()
        }
    }
}
