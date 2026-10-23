//
//  KnockDetector.swift
//  NightPdf
//

// Knock to scroll is iPhone and iPad only: Core Motion has no accelerometer on the Mac.
#if os(iOS)

import CoreMotion
import simd
import SwiftUI

/// A group of jolts close together, and what it was taken for.
struct KnockEvent {
    /// Nil when the group was ignored.
    let knock: Knock?
    let jolts: Int
    /// The strongest jolt in the group, in g.
    let strength: Double
    let number: Int
}

/// Listens to the accelerometer for knocks on the table the device lies on.
/// A knock shows up as a jolt: a sudden change between two samples, which
/// slow movements like picking the device up don't produce.
///
/// One for the app, since a device has one accelerometer (and Core Motion wants
/// one manager): every window's reader registers while it's active, and only
/// the reader in the key window scrolls, so side-by-side windows don't both move.
@Observable
final class KnockDetector {
    static let shared = KnockDetector()

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: "knockToScroll")
            updateScreenLock()
        }
    }
    /// 0 needs a firm knock, 1 picks up a light tap.
    var sensitivity: Double {
        didSet {
            defaults.set(sensitivity, forKey: "knockSensitivity")
            updateSamplerSettings()
        }
    }
    var tripleKnockGoesBack: Bool {
        didSet {
            defaults.set(tripleKnockGoesBack, forKey: "knockTripleGoesBack")
            updateSamplerSettings()
        }
    }

    /// Recent jolt strength in g, held briefly so a meter can show it. Only
    /// updated while a meter is showing (see `meterAppeared()`).
    private(set) var level = 0.0
    private(set) var lastEvent: KnockEvent?
    private(set) var isListening = false

    static let thresholdRange = 0.01...0.5   // g

    var threshold: Double {
        // Log scale, so the slider has as much room for light taps as for firm knocks.
        Self.thresholdRange.upperBound * pow(Self.thresholdRange.lowerBound / Self.thresholdRange.upperBound, sensitivity)
    }

    var isAvailable: Bool { motion.isAccelerometerAvailable }

    /// Keeps the screen on this long after the last knock.
    private static let screenAwakeTime: Duration = .seconds(300)

    private struct Listener {
        weak var owner: AnyObject?
        let isKey: () -> Bool
        let onKnock: (Knock) -> Void
    }

    @ObservationIgnored private let motion = CMMotionManager()
    /// Samples arrive 100 times a second; they're worked through here rather
    /// than on the main thread.
    @ObservationIgnored private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Knock detection"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()
    @ObservationIgnored private let sampler = KnockSampler()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var listeners: [Listener] = []
    @ObservationIgnored private var meterViewers = 0 {
        didSet { sampler.setPublishesLevel(meterViewers > 0) }
    }
    @ObservationIgnored private var screenLockRelease: Task<Void, Never>?

    private init() {
        defaults.register(defaults: [
            "knockSensitivity": 0.5,
            "knockTripleGoesBack": true,
        ])
        isEnabled = defaults.bool(forKey: "knockToScroll")
        sensitivity = defaults.double(forKey: "knockSensitivity")
        tripleKnockGoesBack = defaults.bool(forKey: "knockTripleGoesBack")
        updateSamplerSettings()
    }

    // MARK: - Listeners

    /// Starts the accelerometer if no one was listening. `isKey` tells whether
    /// the listener's window is the key one, which gets the knocks.
    func addListener(_ owner: AnyObject, isKey: @escaping () -> Bool, onKnock: @escaping (Knock) -> Void) {
        listeners.removeAll { $0.owner == nil || $0.owner === owner }
        listeners.append(Listener(owner: owner, isKey: isKey, onKnock: onKnock))
        updateListening()
    }

    func removeListener(_ owner: AnyObject) {
        listeners.removeAll { $0.owner == nil || $0.owner === owner }
        updateListening()
    }

    private func updateListening() {
        if listeners.isEmpty { stop() } else { start() }
        updateScreenLock()
    }

    private func start() {
        guard !isListening, motion.isAccelerometerAvailable else {
            DebugLog.knock("start skipped: listening \(isListening), accelerometer \(motion.isAccelerometerAvailable)")
            return
        }
        DebugLog.knock("""
            start: enabled \(isEnabled), threshold \(DebugLog.g(threshold)) (sensitivity \
            \(sensitivity.formatted(.number.precision(.fractionLength(2))))), triple goes back \(tripleKnockGoesBack)
            """)
        isListening = true
        sampler.start()
        motion.accelerometerUpdateInterval = 1.0 / 100   // the most iOS delivers
        let sampler = sampler
        // Runs on the motion queue; only knocks and meter updates come back to the main thread.
        motion.startAccelerometerUpdates(to: motionQueue) { @Sendable data, _ in
            guard let data else { return }
            let a = data.acceleration
            let output = sampler.process(SIMD3(a.x, a.y, a.z), at: data.timestamp)
            guard output.level != nil || output.group != nil else { return }
            Task { @MainActor in KnockDetector.shared.handle(output) }
        }
    }

    private func stop() {
        guard isListening else { return }
        DebugLog.knock("stop")
        motion.stopAccelerometerUpdates()
        sampler.stop()
        isListening = false
        level = 0
    }

    private func handle(_ output: KnockSampler.Output) {
        guard isListening else { return }   // samples queued before stopping
        if let level = output.level { self.level = level }
        if let group = output.group {
            deliver(group.knock, jolts: group.jolts, strength: group.strength)
        }
    }

    func touchChanged(isDown: Bool) {
        sampler.touchChanged(isDown: isDown)
    }

    /// The settings sheet calls these while its meter is on screen, so the
    /// motion queue only wakes the main thread for the meter then.
    func meterAppeared() {
        meterViewers += 1
    }

    func meterDisappeared() {
        meterViewers = max(meterViewers - 1, 0)
        if meterViewers == 0 { level = 0 }
    }

    /// Acts as if a knock was felt, for trying out what knocks do.
    func simulate(_ knock: Knock) {
        deliver(knock, jolts: knock == .double ? 2 : 3, strength: 0, ignoringEnabled: true)
    }

    private func deliver(_ knock: Knock?, jolts: Int, strength: Double, ignoringEnabled: Bool = false) {
        lastEvent = KnockEvent(knock: knock, jolts: jolts, strength: strength, number: (lastEvent?.number ?? 0) + 1)
        DebugLog.knock("""
            \(ignoringEnabled ? "tried out" : "group of \(jolts)"): \(knock?.title ?? "ignored"), \
            \(knock == nil ? "nothing to do" : isEnabled || ignoringEnabled ? "scrolling" : "not scrolling, Knock to Scroll is off")
            """)
        guard let knock, isEnabled || ignoringEnabled else { return }
        let live = listeners.filter { $0.owner != nil }
        guard let listener = live.last(where: { $0.isKey() }) ?? live.last else {
            DebugLog.knock("no one is handling knocks")
            return
        }
        if isEnabled { keepScreenAwake() }   // trying it out with the feature off shouldn't
        listener.onKnock(knock)
    }

    private func updateSamplerSettings() {
        sampler.update(threshold: threshold, tripleKnockGoesBack: tripleKnockGoesBack)
    }

    // MARK: - Screen lock

    /// Reading hands-free means nobody touches the screen, so while any window
    /// listens for knocks, keep it from locking until a while after the last one.
    private func updateScreenLock() {
        if isListening && isEnabled { keepScreenAwake() } else { allowScreenLock() }
    }

    private func keepScreenAwake() {
        UIApplication.shared.isIdleTimerDisabled = true
        screenLockRelease?.cancel()
        screenLockRelease = Task {
            try? await Task.sleep(for: Self.screenAwakeTime)
            guard !Task.isCancelled else { return }
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func allowScreenLock() {
        screenLockRelease?.cancel()
        screenLockRelease = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
#endif
