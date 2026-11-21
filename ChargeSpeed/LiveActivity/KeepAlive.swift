import CoreLocation
import Foundation
import UIKit

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
///   desliga junto com a Live Activity.
///
/// **Por que "Sempre".** Com "Ao usar o app", o iOS so deixa continuar em segundo
/// plano um servico que foi ligado com o app em uso. Quando o atalho (ou o
/// BGProcessingTask) acorda o app morto, ele ja esta em segundo plano: o pedido
/// de localizacao nao pega, o app volta a dormir depois de uns segundos e a ilha
/// congela ate o proximo atalho. Com "Sempre" o servico liga dali mesmo. O GPS
/// continua desligado; o que muda e que o iOS passa a mostrar, de tempos em
/// tempos, o aviso de que o app usou a localizacao em segundo plano.
@MainActor
final class KeepAlive: NSObject {

    static let shared = KeepAlive()

    private let manager = CLLocationManager()
    private(set) var isActive = false
    /// Ultimo erro do Core Location, para os atalhos responderem algo util.
    private(set) var lastError: String?

    private static let askedAlwaysKey = "askedAlwaysLocation"

    var authorization: CLAuthorizationStatus { manager.authorizationStatus }
    var isAuthorized: Bool {
        authorization == .authorizedAlways || authorization == .authorizedWhenInUse
    }

    /// Texto curto de status, para as acoes dos Atalhos responderem algo util.
    var statusText: String {
        switch authorization {
        case .notDetermined:
            return "abra o app uma vez para autorizar a localizacao"
        case .denied, .restricted:
            return "modo continuo desligado (localizacao negada)"
        case .authorizedWhenInUse:
            return "localizacao em 'Ao usar': o modo continuo so religa com o app aberto. Mude para 'Sempre'"
        default:
            if let lastError { return "modo continuo com erro de localizacao (\(lastError))" }
            return isActive ? "modo continuo ativo" : "modo continuo pronto"
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

    /// Os pedidos de permissao so aparecem com o app em primeiro plano.
    /// Primeiro "Ao usar"; com ele concedido, o pedido de "Sempre" (o iOS mostra
    /// esse segundo pedido uma vez so; depois, so pelos Ajustes).
    func requestAuthorizationIfNeeded() {
        switch authorization {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            askAlwaysOnce()
        default:
            break
        }
    }

    private func askAlwaysOnce() {
        guard UIApplication.shared.applicationState == .active,
              !UserDefaults.standard.bool(forKey: Self.askedAlwaysKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.askedAlwaysKey)
        manager.requestAlwaysAuthorization()
    }

    /// Liga, se ainda nao estiver ligado.
    func start() {
        guard !isActive else { return }
        restart()
    }

    /// Liga de novo mesmo que ja conste como ligado. Pedir de novo e barato, e e
    /// o que conserta o caso em que o pedido anterior foi feito num momento em
    /// que o iOS nao deixou.
    func restart() {
        guard isAuthorized else { return }
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
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastError = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // kCLErrorLocationUnknown e transitorio: o Core Location segue tentando.
        if let code = (error as? CLError)?.code, code == .locationUnknown { return }
        lastError = (error as? CLError).map { "codigo \($0.code.rawValue)" } ?? error.localizedDescription
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if authorization == .authorizedWhenInUse {
            // Acabou de conceder "Ao usar", com o app na frente: emenda o pedido de "Sempre".
            askAlwaysOnce()
        }
        if isAuthorized, LiveActivityController.shared.isRunning {
            restart()
        } else if !isAuthorized {
            stop()
        }
    }
}
