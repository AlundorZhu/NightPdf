//
//  KnockSamplerTests.swift
//  NightPdfTests
//

import Foundation
import Testing
@testable import NightPdf

/// Feeds the sampler synthetic accelerometer samples at 100 Hz.
struct KnockSamplerTests {
    private let rest = SIMD3<Double>(0, 0, -1)
    private let start: TimeInterval = 1_000

    private func makeSampler(tripleKnockGoesBack: Bool = true) -> KnockSampler {
        let sampler = KnockSampler()
        sampler.update(threshold: 0.05, tripleKnockGoesBack: tripleKnockGoesBack)
        sampler.start()
        return sampler
    }

    /// One-sample jolts at the given offsets (seconds), over `duration`; the
    /// groups the sampler reported.
    private func feed(_ sampler: KnockSampler, jolts: [TimeInterval], duration: TimeInterval = 1.5,
                      beforeSample: (TimeInterval) -> Void = { _ in }) -> [(knock: Knock?, jolts: Int)] {
        var groups: [(knock: Knock?, jolts: Int)] = []
        let joltSamples = Set(jolts.map { Int(($0 * 100).rounded()) })
        for sample in 0...Int(duration * 100) {
            let time = start + Double(sample) / 100
            beforeSample(time)
            let value = joltSamples.contains(sample) ? rest + SIMD3(0.3, 0, 0) : rest
            if let group = sampler.process(value, at: time).group {
                groups.append((group.knock, group.jolts))
            }
        }
        return groups
    }

    @Test func twoJoltsAreADoubleKnock() {
        let groups = feed(makeSampler(), jolts: [0.2, 0.4])
        #expect(groups.count == 1)
        #expect(groups.first?.knock == .double)
        #expect(groups.first?.jolts == 2)
    }

    @Test func threeJoltsAreATripleKnock() {
        let groups = feed(makeSampler(), jolts: [0.2, 0.4, 0.6])
        #expect(groups.count == 1)
        #expect(groups.first?.knock == .triple)
    }

    @Test func threeJoltsAreNothingWithoutTripleKnocks() {
        let groups = feed(makeSampler(tripleKnockGoesBack: false), jolts: [0.2, 0.4, 0.6])
        #expect(groups.allSatisfy { $0.knock != .triple })
    }

    @Test func aLoneJoltIsIgnored() {
        let groups = feed(makeSampler(), jolts: [0.2])
        #expect(groups.count == 1)
        #expect(groups.first?.knock == nil)
    }

    @Test func joltsRightAfterATouchAreIgnored() {
        let sampler = makeSampler()
        // A tap at 0.1 s; the jolts come within 250 ms of it.
        let groups = feed(sampler, jolts: [0.15, 0.3]) { time in
            if time == start + 0.1 {
                sampler.touchChanged(isDown: true, at: time)
                sampler.touchChanged(isDown: false, at: time)
            }
        }
        #expect(groups.isEmpty)
    }

    @Test func ringingIsOneJolt() {
        // Jolts 50 ms apart are one knock ringing, so this is two knocks, not four.
        let groups = feed(makeSampler(), jolts: [0.2, 0.25, 0.4, 0.45])
        #expect(groups.first?.knock == .double)
    }
}
