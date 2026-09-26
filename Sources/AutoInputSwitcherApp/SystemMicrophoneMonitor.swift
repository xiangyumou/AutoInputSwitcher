import CoreAudio
import Foundation

/// Watches kAudioDevicePropertyDeviceIsRunningSomewhere on the default input
/// device. Reading this flag does not open the device, so no microphone
/// permission is needed.
@MainActor
final class SystemMicrophoneMonitor: MicrophoneActivityMonitoring {
    private static var defaultInputDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static var runningSomewhereAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private(set) var isRunning = false

    private var handler: (@MainActor (Bool) -> Void)?
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    // The same block objects must be passed back to remove the listeners.
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var runningListener: AudioObjectPropertyListenerBlock?

    func start(_ handler: @escaping @MainActor (Bool) -> Void) {
        self.handler = handler

        guard defaultDeviceListener == nil else { return }

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.attachToDefaultInputDevice()
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &Self.defaultInputDeviceAddress,
            .main,
            listener
        )
        if status == noErr {
            defaultDeviceListener = listener
        }

        attachToDefaultInputDevice()
    }

    func stop() {
        handler = nil
        detachFromDevice()

        if let defaultDeviceListener {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &Self.defaultInputDeviceAddress,
                .main,
                defaultDeviceListener
            )
            self.defaultDeviceListener = nil
        }

        isRunning = false
    }

    private func attachToDefaultInputDevice() {
        let newDeviceID = Self.defaultInputDevice()
        guard newDeviceID != deviceID else { return }

        detachFromDevice()
        deviceID = newDeviceID

        if deviceID != AudioObjectID(kAudioObjectUnknown) {
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated {
                    self?.updateRunningState()
                }
            }
            let status = AudioObjectAddPropertyListenerBlock(
                deviceID,
                &Self.runningSomewhereAddress,
                .main,
                listener
            )
            if status == noErr {
                runningListener = listener
            }
        }

        updateRunningState()
    }

    private func detachFromDevice() {
        if let runningListener, deviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioObjectRemovePropertyListenerBlock(
                deviceID,
                &Self.runningSomewhereAddress,
                .main,
                runningListener
            )
        }
        runningListener = nil
        deviceID = AudioObjectID(kAudioObjectUnknown)
    }

    private func updateRunningState() {
        let running = Self.isRunningSomewhere(deviceID)
        guard running != isRunning else { return }

        isRunning = running
        handler?(running)
    }

    private static func defaultInputDevice() -> AudioObjectID {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputDeviceAddress,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr ? deviceID : AudioObjectID(kAudioObjectUnknown)
    }

    private static func isRunningSomewhere(_ deviceID: AudioObjectID) -> Bool {
        guard deviceID != AudioObjectID(kAudioObjectUnknown) else { return false }

        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &runningSomewhereAddress,
            0,
            nil,
            &size,
            &value
        )
        return status == noErr && value != 0
    }
}
