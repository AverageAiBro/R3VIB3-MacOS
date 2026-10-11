import SwiftUI

struct TranscriptPopoverView: View {
    @EnvironmentObject var appState: AppState
    let text: String
    let isMessageOnly: Bool
    @State private var copied = false

    private var transcript: String { isMessageOnly ? text : appState.lastTranscript }
    private var busy: Bool { appState.isRecording || appState.isTranscribing }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: isMessageOnly ? "info.circle" : "text.bubble")
                    .foregroundColor(.accentColor)
                Text(isMessageOnly ? "R3VIB3" : "Your transcript").font(.headline)
                Spacer()
                if appState.isTranscribing {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Transcribing")
                } else if !isMessageOnly {
                    Text("On-device").font(.caption).foregroundColor(.secondary)
                }
            }
            ScrollView {
                Text(transcript.isEmpty ? "Your next dictation will appear here." : transcript)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .lineSpacing(4)
                    .foregroundColor(transcript.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(height: isMessageOnly ? 100 : 160)
            .background(R3VTheme.canvas, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08), lineWidth: 1))

            if !isMessageOnly {
                HStack(spacing: 10) {
                    Button {
                        appState.copyLastTranscript()
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(transcript.isEmpty)
                    Button("Paste") { appState.pasteLastTranscript() }
                        .buttonStyle(R3VGlassButtonStyle(prominent: true))
                        .disabled(transcript.isEmpty || busy)
                    Spacer()
                    Button { appState.retryTranscription() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Transcribe again")
                        .accessibilityLabel("Retry transcription")
                        .disabled(appState.lastAudioFileURL == nil || busy)
                    Button { appState.clearTranscript() } label: { Image(systemName: "trash") }
                        .help("Clear transcript and recording")
                        .accessibilityLabel("Clear transcript")
                        .disabled((transcript.isEmpty && appState.lastAudioFileURL == nil) || busy)
                }
            }
        }
        .padding(18)
        .frame(width: 420)
        .r3vTheme()
        .onChange(of: transcript) { _ in copied = false }
    }
}
