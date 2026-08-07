import Cocoa

final class MonitorBadgePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class MonitorSelectionOverlayManager {
    private var panels: [MonitorBadgePanel] = []

    func show(numberedDisplays: [NumberedDisplay], eligibleDisplayUUIDs: Set<String>) {
        dismiss()

        for numberedDisplay in numberedDisplays
        where eligibleDisplayUUIDs.contains(numberedDisplay.display.uuid) {
            guard let screen = screen(for: numberedDisplay.display.id) else { continue }
            let panel = makePanel(number: numberedDisplay.number)
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.midY - size.height / 2
            ))
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    func dismiss() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }

    private func makePanel(number: Int) -> MonitorBadgePanel {
        let size = NSSize(width: 112, height: 112)
        let panel = MonitorBadgePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let badge = NSView(frame: NSRect(origin: .zero, size: size))
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.clear.cgColor

        let label = NSTextField(labelWithString: String(number))
        label.alignment = .center
        label.textColor = .labelColor
        label.font = NSFont.monospacedDigitSystemFont(ofSize: number < 10 ? 58 : 46, weight: .bold)
        label.frame = NSRect(x: 0, y: 19, width: size.width, height: 72)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.white.withAlphaComponent(0.9)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = .zero
        label.shadow = shadow
        badge.addSubview(label)

        panel.contentView = badge
        return panel
    }

    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let value = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDirectDisplayID(value.uint32Value) == displayID
        }
    }
}
