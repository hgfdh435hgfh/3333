import SwiftUI

// Liquid Glass arrived with the iOS 26 SDK (Swift 6.2). Everything here falls back to a blurred
// material on earlier systems, and still compiles with older Xcode versions.

extension View {
    /// Puts the view on a Liquid Glass surface of the given shape.
    @ViewBuilder
    func glass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            modifier(FrostedSurface(shape: shape, tint: tint))
        }
        #else
        modifier(FrostedSurface(shape: shape, tint: tint))
        #endif
    }

    /// Background for a sheet that is not full height: the system's own glass on iOS 26, a material before it.
    @ViewBuilder
    func glassSheet() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self
        } else {
            presentationBackground(.ultraThinMaterial)
        }
        #else
        presentationBackground(.ultraThinMaterial)
        #endif
    }
}

/// The pre-iOS 26 stand-in for glass: a blurred material with a hairline edge.
private struct FrostedSurface<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background((tint ?? Color.clear).opacity(0.28), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}

/// Groups neighbouring glass surfaces so the system can draw them together.
struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer { content() }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}
