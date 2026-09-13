# ChargeSpeed (ios-charging-monitor)

Personal dev-only iPhone app: live charge power in watts from private APIs. Not App Store safe.

## Build and deploy

- XcodeGen project: `xcodegen generate` after editing `project.yml` or adding files.
- Scheme `ChargeSpeed`, bundle id `com.gregwilson.chargespeed`, team in `project.yml`.
- Deploy: `/deploy-to-iphone`. Console-attached launch (phone unlocked):
  `xcrun devicectl device process launch --console --terminate-existing --device <UDID> com.gregwilson.chargespeed`
- Simulator runs but IOKit calls hit the Mac, so it shows the Mac's battery.
- Release IPA: `.github/workflows/release.yml` builds an unsigned IPA on any `v*` tag and attaches it to a
  GitHub release. To ship: bump `MARKETING_VERSION` in `project.yml`, `git tag vX.Y.Z && git push origin vX.Y.Z`.
  Keep it unsigned; a signed IPA embeds the team, certificate, and registered device UDIDs.

## Code

- `IOKitBattery.swift`: dlsym'd IOKit. `IOPMPowerSource` registry (sandbox leaves 2 keys on iOS), powerd `IOPSCopyPowerSourcesInfo`, `IOPSCopyExternalPowerAdapterDetails`, `IOPSCopyChargeStatus` (always refused).
- `HIDSensors.swift`: `IOHIDEventSystemClient`, usage page 0xff08 (usage 2 = A, 3 = V), 0xff00/5 = temps. One client per process; created once.
- `PowerSnapshot.swift`: merges sources. Headline = `Charger VQ0u × IQ0u` (USB-C input). `IQ0B × VQ0l` = into battery. `VQ1u` = MagSafe rail voltage (no wireless input current sensor exists, so MagSafe input watts are unavailable; headline falls back to battery watts). `gas gauge battery` (several; app shows the max), `Charger TQ0j`, `PMU tdie*` = temps. Throttling flag = `ProcessInfo.thermalState` serious/critical; battery colored ≥38 °C amber, ≥42 °C red.
- `PowerMonitor.swift`: 1 s poll, %-rate fallback (`batteryWattHours` = 19.7 for 17 Pro Max), hold detection with 45 s debounce, peak of the headline watts per charging session (median of last 3 samples; resets at plug-in, survives full/top-off and relaunch via persisted session identity: adapter serial + last-seen plugged/percent; manual reset button).
- `SmartCharge.m`: PowerUI client, blocked on iOS, kept for macOS/entitled builds. `Probes*.swift/.m`: DEBUG exploration only, not called.

## Verified blocked on iOS 26 (don't retry)

IOKit battery registry keys beyond `BatteryInstalled`/`ExternalConnected`; `IOReport`; `IOPMCopyBatteryInfo`;
`IOPSCopyChargeStatus`, `IOPSCopyBatteryLevelLimits`, `IOPSCopyPowerSourcesInfoPrecise` (all kIOReturnNotPrivileged);
PowerUI XPC (Optimized Charging / charge limit settings); CFPreferences of other domains; powerd `Time to Empty` (always 0);
any discharge-current sensor (none exists in the 75 HID services). Darwin notify `smartchargestatuschanged` state is always 0.
