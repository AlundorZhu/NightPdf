//
//  KnockDetector.swift
//  NightPdf
//

import CoreMotion
import os
import simd
import SwiftUI

nonisolated enum Knock {
    case double, triple

    var title: String {
        switch self {
        case .double: "Double knock"
        case .triple: "Triple knock"
        }
    }
}

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
        keepScreenAwake()
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

/// Turns accelerometer samples into groups of jolts, on the motion queue.
/// Touches and setting changes arrive from the main thread, so the state is
/// behind a lock.
nonisolated final class KnockSampler: Sendable {
    struct Output: Sendable {
        /// The meter's new level, about 25 times a second while it's showing.
        var level: Double?
        var group: (knock: Knock?, jolts: Int, strength: Double)?
    }

    /// Jolts closer together than this are one knock still ringing.
    private static let ringDown: TimeInterval = 0.1
    /// How long to wait for another knock before acting on the ones so far.
    private static let nextKnockWindow: TimeInterval = 0.35
    /// When no third knock is expected, a short wait still lets a screen tap
    /// cancel the jolt it caused.
    private static let touchWindow: TimeInterval = 0.08
    /// Touching the screen jolts the device, so knocks are ignored around touches.
    private static let touchQuietPeriod: TimeInterval = 0.25

    private struct State: Sendable {
        var isRunning = false
        var publishesLevel = false
        var threshold = 0.0
        var tripleKnockGoesBack = true
        var isTouching = false
        var previous: SIMD3<Double>?
        var lastJolt: TimeInterval = 0
        var lastTouch: TimeInterval = 0
        var pendingJolts = 0
        var pendingStrength = 0.0
        var heldLevel = 0.0
        var samplesSinceMeter = 0
        #if DEBUG
        var rateStart: TimeInterval = 0
        var rateSamples = 0
        #endif
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func start() {
        state.withLock { $0.isRunning = true }
    }

    func stop() {
        state.withLock { state in
            state.isRunning = false
            state.previous = nil
            state.pendingJolts = 0
            state.heldLevel = 0
        }
    }

    func update(threshold: Double, tripleKnockGoesBack: Bool) {
        state.withLock { state in
            state.threshold = threshold
            state.tripleKnockGoesBack = tripleKnockGoesBack
        }
    }

    func setPublishesLevel(_ publishes: Bool) {
        state.withLock { $0.publishesLevel = publishes }
    }

    /// `time` is on the clock sample timestamps use.
    func touchChanged(isDown: Bool, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        state.withLock { state in
            state.isTouching = isDown
            state.lastTouch = time
            DebugLog.knock("""
                touch \(isDown ? "down" : "up")\
                \(isDown && state.pendingJolts > 0 ? ", dropping \(state.pendingJolts) pending" : "")
                """)
            if isDown { state.pendingJolts = 0 }
        }
    }

    func process(_ sample: SIMD3<Double>, at time: TimeInterval) -> Output {
        state.withLock { state in
            guard state.isRunning else { return Output() }
            defer { state.previous = sample }
            guard let previous = state.previous else { return Output() }

            #if DEBUG
            Self.logSampleRate(at: time, &state)
            #endif

            var output = Output()
            let jolt = length(sample - previous)
            output.level = Self.updateMeter(with: jolt, &state)

            let threshold = state.threshold
            let quiet = state.isTouching || time - state.lastTouch < Self.touchQuietPeriod
            let sinceLast = time - state.lastJolt
            let counts = !quiet && jolt >= threshold && sinceLast >= Self.ringDown
            // Half the threshold and up, so near misses show when tuning.
            if jolt >= threshold / 2 {
                DebugLog.knock("""
                    jolt \(DebugLog.g(jolt)) vs \(DebugLog.g(threshold)): \
                    \(counts ? "counted #\(state.pendingJolts + 1), \(DebugLog.ms(sinceLast)) after the last"
                        : state.isTouching ? "ignored, touching the screen"
                        : time - state.lastTouch < Self.touchQuietPeriod
                            ? "ignored, \(DebugLog.ms(time - state.lastTouch)) after a touch"
                        : jolt < threshold ? "below threshold"
                        : "ringing, \(DebugLog.ms(sinceLast)) after the last")
                    """)
            }

            if quiet {
                if state.pendingJolts > 0 { DebugLog.knock("dropping \(state.pendingJolts) pending jolts") }
                state.pendingJolts = 0
            } else if counts {
                state.lastJolt = time
                state.pendingJolts += 1
                state.pendingStrength = state.pendingJolts == 1 ? jolt : max(state.pendingStrength, jolt)
            }

            let pendingJolts = state.pendingJolts
            let expectsMore = pendingJolts < 2 || (pendingJolts == 2 && state.tripleKnockGoesBack)
            let window = expectsMore ? Self.nextKnockWindow : Self.touchWindow
            guard pendingJolts > 0, time - state.lastJolt > window else { return output }
            let knock: Knock? = switch pendingJolts {
            case 2: .double
            case 3 where state.tripleKnockGoesBack: .triple
            default: nil   // a lone jolt, or a burst like typing
            }
            output.group = (knock, pendingJolts, state.pendingStrength)
            state.pendingJolts = 0
            return output
        }
    }

    #if DEBUG
    /// Every 5 seconds, so it's clear samples arrive at the rate the timing assumes.
    private static func logSampleRate(at time: TimeInterval, _ state: inout State) {
        state.rateSamples += 1
        if state.rateStart == 0 { state.rateStart = time }
        guard time - state.rateStart >= 5 else { return }
        DebugLog.knock("""
            \(Int((Double(state.rateSamples) / (time - state.rateStart)).rounded())) samples/s, \
            touching \(state.isTouching)
            """)
        state.rateStart = time
        state.rateSamples = 0
    }
    #endif

    /// Holds peaks for a moment and publishes about 25 times a second, which
    /// is plenty for a meter and keeps SwiftUI from redrawing at 100 Hz.
    private static func updateMeter(with jolt: Double, _ state: inout State) -> Double? {
        state.heldLevel = max(jolt, state.heldLevel * 0.97)
        state.samplesSinceMeter += 1
        guard state.samplesSinceMeter >= 4 else { return nil }
        state.samplesSinceMeter = 0
        return state.publishesLevel ? state.heldLevel : nil
    }
}
