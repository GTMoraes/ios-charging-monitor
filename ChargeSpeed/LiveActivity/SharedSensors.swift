import Foundation

/// Um cliente HID por processo.
///
/// O upstream documenta que um segundo `IOHIDEventSystemClient` no mesmo processo
/// le NaN. Cada `PowerMonitor` abria o seu: o da tela do app, o de cada execucao
/// do atalho e o do segundo plano. O workflow troca `HIDSensors()` por
/// `HIDSensors.shared` no `PowerMonitor` na hora do build, para o arquivo do
/// upstream continuar intocado no fork.
extension HIDSensors {
    static let shared: HIDSensors? = HIDSensors()
}
