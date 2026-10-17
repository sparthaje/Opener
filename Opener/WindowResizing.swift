import Cocoa
import ApplicationServices

enum ResizeDirection {
    case left
    case right
}

/// Horizontal resizing of the focused window on a grid of tenths of its
/// monitor's usable width. Each press moves to the next grid width in the
/// direction of the change, so an off-grid window lands on the grid: from
/// 0.25, growing gives 0.4 and shrinking gives 0.1. Widths stay within
/// 0.1...1.0. The boundary that moves depends on where the window sits:
/// - docked to the right edge: the left boundary moves (`.left` grows),
/// - docked to the left edge: the right boundary moves (`.right` grows),
/// - docked to both edges: the boundary opposite the key moves inward,
/// - floating: it resizes about its center (`.right` grows, `.left` shrinks).
final class WindowResizer {
    // Grid spacing as a fraction of the monitor's usable width.
    private static let stepFraction: CGFloat = 0.10
    private static let gridSteps = 10
    // Widths within this fraction of a step of a grid line count as on it, so
    // apps that round their width (terminals sizing to whole cells) still step
    // to the next line instead of re-snapping to the current one.
    private static let gridTolerance: CGFloat = 0.1
    // Apps and tiling tools often leave a small gap at the screen edge, so a
    // window this close to an edge still counts as docked to it.
    private static let edgeTolerance: CGFloat = 8

    private enum Anchor {
        case minX
        case maxX
        case center
    }

    func resizeFocusedWindow(_ direction: ResizeDirection) {
        guard let window = WindowRouter.systemFocusedWindow(),
              !isFullScreen(window),
              let frame = WindowRouter.axFrame(of: window),
              let bounds = usableHorizontalBounds(for: frame) else {
            return
        }

        let (target, anchor) = Self.resizedFrame(frame, within: bounds, direction: direction)
        guard target != frame else { return }
        withEnhancedUserInterfaceDisabled(for: window) {
            apply(target, anchoredAt: anchor, from: frame, to: window)
        }
    }

    private static func resizedFrame(
        _ frame: CGRect,
        within bounds: ClosedRange<CGFloat>,
        direction: ResizeDirection
    ) -> (CGRect, Anchor) {
        let boundsWidth = bounds.upperBound - bounds.lowerBound
        let step = boundsWidth * stepFraction
        let touchesLeft = frame.minX <= bounds.lowerBound + edgeTolerance
        let touchesRight = frame.maxX >= bounds.upperBound - edgeTolerance

        let grows: Bool
        let anchor: Anchor
        switch (touchesLeft, touchesRight, direction) {
        case (true, true, .left):
            (grows, anchor) = (false, .minX)
        case (true, true, .right):
            (grows, anchor) = (false, .maxX)
        case (true, false, _):
            (grows, anchor) = (direction == .right, .minX)
        case (false, true, _):
            (grows, anchor) = (direction == .left, .maxX)
        case (false, false, _):
            (grows, anchor) = (direction == .right, .center)
        }

        let steps = frame.width / step
        let targetSteps = grows
            ? Int((steps + 1 - gridTolerance).rounded(.up))
            : Int((steps - 1 + gridTolerance).rounded(.down))
        let width = CGFloat(min(max(targetSteps, 1), gridSteps)) * step

        // Docked edges snap to the screen edge so grid widths are exact.
        let minX: CGFloat
        switch anchor {
        case .minX:
            minX = bounds.lowerBound
        case .maxX:
            minX = bounds.upperBound - width
        case .center:
            minX = min(max(frame.midX - width / 2, bounds.lowerBound), bounds.upperBound - width)
        }
        return (CGRect(x: minX, y: frame.minY, width: width, height: frame.height), anchor)
    }

    private func apply(_ target: CGRect, anchoredAt anchor: Anchor, from frame: CGRect, to window: AXUIElement) {
        // Move before growing leftward and resize before moving rightward, so
        // the window never passes beyond the screen edge mid-change, where
        // some applications clamp the requested frame.
        if target.minX < frame.minX {
            setPosition(target.origin, of: window)
            setSize(target.size, of: window)
        } else {
            setSize(target.size, of: window)
            setPosition(target.origin, of: window)
        }

        // Applications may enforce their own minimum or stepped widths. Re-pin
        // the anchored edge to whatever width was actually accepted.
        guard let actual = WindowRouter.axFrame(of: window), actual.width != target.width else { return }
        let x: CGFloat
        switch anchor {
        case .minX: x = target.minX
        case .maxX: x = target.maxX - actual.width
        case .center: x = target.midX - actual.width / 2
        }
        setPosition(CGPoint(x: x, y: target.minY), of: window)
    }

    private func usableHorizontalBounds(for frame: CGRect) -> ClosedRange<CGFloat>? {
        guard let display = DisplayGeometry.display(for: frame, among: DisplayGeometry.activeDisplays()),
              let screen = NSScreen.screens.first(where: {
                  ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.id
              }) else {
            return nil
        }
        // Cocoa and Core Graphics differ only in their vertical axis, so the
        // visible frame's x range (excluding a side-mounted Dock) applies as-is.
        let visible = screen.visibleFrame
        return visible.minX...visible.maxX
    }

    private func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value) == .success else {
            return false
        }
        return (value as? Bool) ?? false
    }

    /// Chromium and Electron apps enable AXEnhancedUserInterface when they detect
    /// assistive tooling, which makes them animate and partially ignore AX frame
    /// changes. Window managers disable it for the duration of the change.
    private func withEnhancedUserInterfaceDisabled(for window: AXUIElement, _ body: () -> Void) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else {
            body()
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        let attribute = "AXEnhancedUserInterface" as CFString
        var value: CFTypeRef?
        let enabled = AXUIElementCopyAttributeValue(appElement, attribute, &value) == .success
            && (value as? Bool) == true

        if enabled { AXUIElementSetAttributeValue(appElement, attribute, kCFBooleanFalse) }
        body()
        if enabled { AXUIElementSetAttributeValue(appElement, attribute, kCFBooleanTrue) }
    }

    private func setPosition(_ point: CGPoint, of window: AXUIElement) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    private func setSize(_ size: CGSize, of window: AXUIElement) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }
}
