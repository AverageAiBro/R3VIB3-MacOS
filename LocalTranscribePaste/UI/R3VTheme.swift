import AppKit
import SwiftUI

/// The same neutral, dark Liquid Glass palette as Death Eater.
enum R3VTheme {
    static let canvas = Color.black.opacity(0.18)
    static let accent = Color(white: 0.82)
    static let selection = Color.white.opacity(0.12)
    static let glass = Glass.regular.tint(.black.opacity(0.22))
    static let windowGlass = Glass.clear.tint(.black.opacity(0.22))

    static func configure(_ window: NSWindow, fullSizeContent: Bool = false) {
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        if fullSizeContent {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
        }
    }
}

extension View {
    func r3vTheme(window: Bool = false) -> some View {
        self
            .preferredColorScheme(.dark)
            .environment(\.colorScheme, .dark)
            .tint(R3VTheme.accent)
            .accentColor(R3VTheme.accent)
            .buttonStyle(R3VGlassButtonStyle())
            .modifier(R3VWindowSurface(enabled: window))
    }
}

struct R3VGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(prominent ? .semibold : .regular)
            .foregroundStyle(.white.opacity(enabled ? 0.92 : 0.3))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(R3VTheme.glass.interactive(), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(contrast == .increased ? 0.6 : prominent ? 0.28 : 0.09), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.65 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct R3VWindowSurface: ViewModifier {
    let enabled: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if enabled {
            content.background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.black.opacity(reduceTransparency ? 1 : 0.24))
                    .glassEffect(R3VTheme.windowGlass, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .ignoresSafeArea()
            }
            .background(R3VWindowTransparency().ignoresSafeArea())
        } else {
            content
        }
    }
}

/// Apply after hosting attaches: AppKit may set a backing while creating the controller.
private struct R3VWindowTransparency: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { TransparentWindowView() }
    func updateNSView(_ view: NSView, context: Context) {}
}

private final class TransparentWindowView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { R3VTheme.configure(window, fullSizeContent: true) }
    }
}
