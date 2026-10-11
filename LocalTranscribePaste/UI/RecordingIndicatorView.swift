import SwiftUI

enum IndicatorMode {
    case recording
    case pasteReady
    case transcribing
}

struct RecordingIndicatorView: View {
    let mode: IndicatorMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var text: String {
        switch mode {
        case .recording:
            return "Recording"
        case .pasteReady:
            return "Paste ready"
        case .transcribing:
            return "Transcribing"
        }
    }

    private var color: Color {
        switch mode {
        case .recording:
            return .red
        case .pasteReady:
            return .green
        case .transcribing:
            return .accentColor
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            indicator
            Text(text)
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(R3VTheme.glass, in: Capsule())
        .padding(4)
        .r3vTheme()
    }

    @ViewBuilder
    private var indicator: some View {
        if mode == .recording {
            if reduceMotion {
                Image(systemName: "mic.fill").foregroundColor(color)
            } else {
                WaveformBars(color: color)
            }
        } else if mode == .transcribing {
            ProgressView().controlSize(.small)
        } else {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
    }
}

private struct WaveformBars: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    let phase = t * 2.2 + Double(index) * 0.8
                    let amplitude = 0.3 + 0.7 * abs(sin(phase))
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color)
                        .frame(width: 3, height: 6 + amplitude * 12)
                }
            }
            .frame(width: 24, height: 18, alignment: .center)
        }
    }
}
