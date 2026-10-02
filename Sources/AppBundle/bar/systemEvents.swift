import AudioToolbox
import CoreAudio
import Foundation
import IOKit.ps

/// "ac" | "battery" | nil (unknown / no power source info)
func currentPowerSource() -> String? {
    guard let info = unsafe IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let type = unsafe IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return nil }
    switch type {
        case kIOPSACPowerValue: return "ac"
        case kIOPSBatteryPowerValue: return "battery"
        default: return nil
    }
}

private func defaultOutputDevice() -> AudioDeviceID? {
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain,
    )
    let status = unsafe AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
    return status == noErr && device != 0 ? device : nil
}

private let volumeAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
    mScope: kAudioDevicePropertyScopeOutput,
    mElement: kAudioObjectPropertyElementMain,
)

/// 0...100, nil without an output device that exposes a main volume (e.g. some HDMI outputs, CI)
func currentVolumeLevel() -> Int? {
    guard let device = defaultOutputDevice() else { return nil }
    var address = volumeAddress
    guard unsafe AudioObjectHasProperty(device, &address) else { return nil }
    var volume = Float32(0)
    var size = UInt32(MemoryLayout<Float32>.size)
    guard unsafe AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }
    return Int((volume * 100).rounded())
}

@MainActor private var lastPowerSource: String? = nil
@MainActor private var lastVolume: Int? = nil
@MainActor private var volumeListener: (device: AudioDeviceID, block: AudioObjectPropertyListenerBlock)? = nil

/// Call once at startup. Sends `power` on AC/battery changes and `volume` on output volume changes.
/// Registration failures are logged once; plugins still run on their intervals.
@MainActor func startSystemEvents() {
    lastPowerSource = currentPowerSource()
    if let source = unsafe IOPSNotificationCreateRunLoopSource({ _ in
        MainActor.assumeIsolated { emitPowerIfChanged() }
    }, nil)?.takeRetainedValue() {
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) // also while a popup menu is tracking
    } else {
        print("HyprDarwin: power source notifications unavailable")
    }

    lastVolume = currentVolumeLevel()
    listenToVolume()
    var defaultDevice = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain,
    )
    _ = unsafe AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultDevice, DispatchQueue.main) { _, _ in
        MainActor.assumeIsolated {
            listenToVolume() // output switched (headphones, HDMI): follow the new device
            emitVolumeIfChanged()
        }
    }
}

@MainActor private func listenToVolume() {
    let current = unsafe volumeListener?.device
    guard let device = defaultOutputDevice(), device != current else { return }
    var address = volumeAddress
    if let old = unsafe volumeListener { // one listener at a time: switching back to a device must not stack blocks
        _ = unsafe AudioObjectRemovePropertyListenerBlock(old.device, &address, DispatchQueue.main, old.block)
    }
    let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { emitVolumeIfChanged() } }
    if unsafe AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main, block) == noErr {
        unsafe volumeListener = (device, block)
    }
}

@MainActor private func emitPowerIfChanged() {
    let source = currentPowerSource()
    guard let source, source != lastPowerSource else { return } // IOPS also fires on every battery % change
    lastPowerSource = source
    PluginHost.shared.send(.power, encodePluginEvent(.power, ["source": source]))
}

@MainActor private func emitVolumeIfChanged() {
    guard let level = currentVolumeLevel(), level != lastVolume else { return }
    lastVolume = level
    PluginHost.shared.send(.volume, encodePluginEvent(.volume, ["level": level]))
}
