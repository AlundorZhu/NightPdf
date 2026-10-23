//
//  KnockSampler.swift
//  NightPdf
//

// The detection logic has no Core Motion or UIKit in it, so it builds (and is
// tested) on the Mac too; only KnockDetector, which feeds it, is iOS only.

import Foundation
import os
import simd

nonisolated enum Knock {
    case double, triple

    var title: String {
        switch self {
        case .double: "Double knock"
        case .triple: "Triple knock"
        }
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
