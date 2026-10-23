//
//  KnockSettingsView.swift
//  NightPdf
//

import SwiftUI

/// Leaves the page showing and responding, so knocks can be tried out while
/// adjusting the sensitivity: at half height on iPhone, and as a centered
/// form on iPad, where a half-height sheet would cut the settings off.
struct KnockSettingsView: View {
    @Bindable var knocks: KnockDetector
    let isRegularWidth: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // A NavigationStack here would inherit DocumentGroup's back button.
            HStack {
                Text("Knock to Scroll")
                    .font(.headline)
                Spacer()
                Button("Done", systemImage: "xmark", role: .close) { dismiss() }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .labelStyle(.iconOnly)
                    .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)

            Form {
                Section {
                    Toggle("Knock to Scroll", isOn: $knocks.isEnabled)
                } footer: {
                    Text(knocks.tripleKnockGoesBack
                         ? "Lay your device on a table and knock beside it. Two knocks scroll forward, three scroll back."
                         : "Lay your device on a table and knock beside it. Two knocks scroll forward.")
                }

                if !knocks.isAvailable {
                    Section {
                        Label("This device has no motion sensor. Use Try It below to see what a knock does.",
                              systemImage: "exclamationmark.triangle")
                    }
                }

                Section {
                    KnockMeter(level: knocks.level, threshold: knocks.threshold)
                    // Runs the same way as the meter: right needs a firmer knock.
                    Slider(value: firmness, in: 0...1) {
                        Text("Knock Strength")
                    } minimumValueLabel: {
                        Text("Light").font(.caption)
                    } maximumValueLabel: {
                        Text("Firm").font(.caption)
                    }
                    LabeledContent("Threshold", value: Self.strength(knocks.threshold))
                    LabeledContent("Last Knock", value: lastKnock)
                } header: {
                    Text("Knock Strength")
                } footer: {
                    Text("Knock and watch the meter. Jolts past the line count as knocks. Slide toward Light until a gentle knock crosses the line, and toward Firm if the page scrolls on its own.")
                }

                Section {
                    Toggle("Triple Knock Scrolls Back", isOn: $knocks.tripleKnockGoesBack)
                } footer: {
                    Text("Listening for a third knock makes double knocks wait a moment.")
                }

                Section("Try It") {
                    Button("Double Knock", systemImage: "arrow.down") { knocks.simulate(.double) }
                    Button("Triple Knock", systemImage: "arrow.up") { knocks.simulate(.triple) }
                }
            }
        }
        // A Form has no height of its own, so give the centered form one that
        // fits every setting.
        .frame(idealHeight: isRegularWidth ? 900 : nil)
        .presentationSizing(.form.fitted(horizontal: false, vertical: isRegularWidth))
        .presentationDetents(isRegularWidth ? [.large] : [.medium, .large])
        .presentationBackgroundInteraction(isRegularWidth ? .enabled : .enabled(upThrough: .medium))
        .onAppear { knocks.meterAppeared() }
        .onDisappear { knocks.meterDisappeared() }
    }

    private var firmness: Binding<Double> {
        Binding { 1 - knocks.sensitivity } set: { knocks.sensitivity = 1 - $0 }
    }

    private var lastKnock: String {
        guard let event = knocks.lastEvent else { return "None yet" }
        guard let knock = event.knock else {
            return "Ignored \(event.jolts) \(event.jolts == 1 ? "jolt" : "jolts"), \(Self.strength(event.strength))"
        }
        guard event.strength > 0 else { return "\(knock.title) (tried out)" }
        return "\(knock.title), \(Self.strength(event.strength))\(knocks.isEnabled ? "" : " (off)")"
    }

    static func strength(_ g: Double) -> String {
        "\(g.formatted(.number.precision(.fractionLength(g < 0.1 ? 3 : 2)))) g"
    }
}

/// The live jolt strength on the same log scale as the slider, with a line
/// at the threshold.
private struct KnockMeter: View {
    let level: Double
    let threshold: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(level >= threshold ? Color.accentColor : .secondary)
                    .frame(width: max(width * Self.position(of: level), 8))
                Rectangle()
                    .fill(.primary)
                    .frame(width: 2)
                    .offset(x: width * Self.position(of: threshold) - 1)
            }
        }
        .frame(height: 12)
        .padding(.vertical, 6)
        .accessibilityElement()
        .accessibilityLabel("Jolt strength")
        .accessibilityValue("\(KnockSettingsView.strength(level)), threshold \(KnockSettingsView.strength(threshold))")
    }

    /// Spans a little past the slider's range so the extremes stay visible.
    private static func position(of g: Double) -> Double {
        let low = KnockDetector.thresholdRange.lowerBound / 2
        let high = KnockDetector.thresholdRange.upperBound * 2
        return min(max(log(g / low) / log(high / low), 0), 1)
    }
}
