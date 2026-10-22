#if os(macOS)
import AppKit
import SwiftUI

/// Receives wheel events only inside the poster fan. Vertical page scrolling passes through.
struct CarouselTrackpadInput: NSViewRepresentable {
    let onScroll: (Double) -> Void
    func makeNSView(context: Context) -> WheelSurface { let view = WheelSurface(); view.onScroll = onScroll; return view }
    func updateNSView(_ view: WheelSurface, context: Context) { view.onScroll = onScroll }
    static func dismantleNSView(_ view: WheelSurface, coordinator: ()) { view.stopMonitoring() }

    final class WheelSurface: NSView {
        var onScroll: (Double) -> Void = { _ in }
        private var monitor: Any?
        private var horizontal: Bool?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }
        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil; horizontal = nil
        }
        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window == window else { return event }
            let inside = bounds.contains(convert(event.locationInWindow, from: nil)) && !visibleRect.isEmpty
            guard inside || horizontal == true else { return event }
            if event.phase.contains(.began) { horizontal = nil }
            let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
            if horizontal == nil, abs(dx) + abs(dy) > 0.01 { horizontal = abs(dx) > abs(dy) }
            let consume = horizontal == true
            let terminal = event.phase.contains(.ended) || event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended)
            if consume { onScroll(Double(event.hasPreciseScrollingDeltas ? dx : dx * 8)) }
            if terminal || (event.phase.isEmpty && event.momentumPhase.isEmpty) { horizontal = nil }
            return consume ? nil : event
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
#endif
