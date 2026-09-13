import Foundation

/// Estimativa de quanto falta para a bateria chegar num nivel alvo.
///
/// Uma regra de tres simples erraria muito, porque a potencia de carga nao e
/// constante: acima de ~50% o iPhone sai da fase de corrente constante e a
/// potencia cai progressivamente. Aqui a conta e integrada de 1 em 1%, aplicando
/// um fator de afunilamento a cada passo.
enum ChargeETA {

    /// Fator de potencia relativo por nivel de bateria. 1.0 ate 50%, caindo
    /// linearmente ate ~0.12 em 100%. E uma aproximacao — calibravel depois com
    /// os dados reais que o proprio app coletar.
    static func taper(at percent: Double) -> Double {
        if percent < 50 { return 1.0 }
        if percent > 100 { return 0.12 }
        return max(0.12, 1.0 - (percent - 50) / 50 * 0.88)
    }

    /// Momento estimado em que a bateria alcanca `target`.
    /// - Parameter measuredWatts: potencia medida AGORA, no nivel `percent`.
    ///   Ela ja embute o afunilamento do nivel atual, por isso o fator e
    ///   normalizado pelo fator do ponto de medicao.
    static func estimate(from percent: Int,
                         to target: Int,
                         measuredWatts: Double,
                         batteryWattHours: Double,
                         now: Date = .now) -> Date? {
        guard percent < target,
              measuredWatts > 0.5,
              batteryWattHours > 0 else { return nil }

        let reference = taper(at: Double(percent))
        guard reference > 0 else { return nil }

        let wattHoursPerPercent = batteryWattHours / 100
        var seconds = 0.0
        for p in percent..<target {
            let factor = taper(at: Double(p) + 0.5) / reference
            let watts = measuredWatts * factor
            guard watts > 0.1 else { return nil }
            seconds += wattHoursPerPercent / watts * 3600
        }

        guard seconds.isFinite, seconds > 60, seconds < 24 * 3600 else { return nil }
        return now.addingTimeInterval(seconds)
    }
}
