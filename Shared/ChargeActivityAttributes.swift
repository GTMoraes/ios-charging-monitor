import ActivityKit
import Foundation

/// Estado compartilhado entre o app e a extensao da Live Activity.
/// Este arquivo e compilado nos DOIS alvos, entao nao pode depender de nada do app.
struct ChargeActivityAttributes: ActivityAttributes, Equatable {

    /// A parte que muda ao longo da sessao de carga.
    struct ContentState: Codable, Hashable {
        /// Watts da ultima medicao: da tomada no cabo, na bateria no sem fio.
        var watts: Double
        var wattsLabel: String
        /// Watts entrando na bateria — o numero honesto para comparar carregadores,
        /// porque nao mistura o consumo do aparelho.
        var intoBatteryWatts: Double?

        var percent: Int
        var targetPercent: Int

        /// Quando a carga deve alcancar `targetPercent`. O iOS renderiza a contagem
        /// sozinho, sem precisar de nenhuma atualizacao nossa — e o truque que faz
        /// a previsao continuar andando com o app fechado.
        var eta: Date?
        /// Inicio do intervalo, para a contagem e a barra.
        var etaStart: Date

        var onHold: Bool
        var isWireless: Bool
        var inputVoltage: Double?
        var inputCurrent: Double?
        var batteryTempC: Double?
        var peakWatts: Double?
        /// iOS declarou estado termico serio/critico — a carga esta sendo cortada.
        var throttling: Bool
        /// Monitor continuo ativo: o app esta medindo com a tela apagada.
        var continuous: Bool

        /// Instante da leitura que gerou este estado.
        var measuredAt: Date
        /// Quantas leituras entraram na Live Activity nesta sessao.
        var updateCount: Int
        /// Ultima vez que o iOS acordou o app em segundo plano, e por qual mecanismo.
        /// E a medicao do experimento: se ficar parado por horas, o background nao roda.
        var lastBackgroundWake: Date?
        var lastBackgroundKind: String?
    }

    /// Estatico na sessao: so muda se voce trocar de carregador.
    var adapterName: String
    var negotiated: String
}

extension ChargeActivityAttributes.ContentState {
    /// Intervalo valido para as contagens do SwiftUI, ou nil quando nao ha previsao.
    var etaRange: ClosedRange<Date>? {
        guard let eta, eta > etaStart else { return nil }
        return etaStart...eta
    }

    var showsETA: Bool { !onHold && etaRange != nil }
}
