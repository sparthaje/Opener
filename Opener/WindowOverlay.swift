//
//  WindowOverlay.swift
//  Opener
//
//  Floating glass overlay for window selection with drag-to-reorder.
//

import Cocoa

// MARK: - Persistence

struct WindowOrderPersistence {
    static let path = (NSHomeDirectory() as NSString).appendingPathComponent(".opener_window_order")

    typealias AppOrderMap = [String: [String: Int]]

    static func load() -> AppOrderMap {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? AppOrderMap else {
            return [:]
        }
        return json
    }

    static func save(_ map: AppOrderMap) {
        guard let data = try? JSONSerialization.data(withJSONObject: map, options: [.prettyPrinted, .sortedKeys]) else { return }
        FileManager.default.createFile(atPath: path, contents: data)
    }

    static func preferredOrder(forApp appPath: String) -> [String: Int] {
        return load()[appPath] ?? [:]
    }

    static func updateOrder(forApp appPath: String, titleToNumber: [String: Int]) {
        var map = load()
        map[appPath] = titleToNumber
        save(map)
    }
}

// MARK: - Rounded mask helper

private func roundedMaskImage(size: NSSize, cornerRadius: CGFloat) -> NSImage {
    return NSImage(size: size, flipped: false) { rect in
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        return true
    }
}

// MARK: - Overlay Panel

class WindowOverlayPanel: NSPanel {

    private let contentContainer = WindowOverlayContentView()
    private var onReorder: (([String]) -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = contentContainer
    }

    func showOverlay(
        windows: [(number: Int, title: String, windowID: CGWindowID, pid: pid_t)],
        onReorder: @escaping ([String]) -> Void
    ) {
        self.onReorder = onReorder
        contentContainer.configure(with: windows) { [weak self] newTitleOrder in
            self?.onReorder?(newTitleOrder)
        }

        let panelSize = contentContainer.idealSize
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let origin = NSPoint(
            x: screenFrame.minX + 20,
            y: screenFrame.maxY - panelSize.height - 20
        )
        setFrame(NSRect(origin: origin, size: panelSize), display: true)

        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 1
        }
    }

    func hideOverlay() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.contentContainer.tearDown()
        })
    }
}

// MARK: - Content View

class WindowOverlayContentView: NSView {

    static let rowHeight: CGFloat = 36
    static let rowSpacing: CGFloat = 10
    static let numberSize: CGFloat = 36
    static let horizontalGap: CGFloat = 16
    static let padding: CGFloat = 20
    static let maxTitleWidth: CGFloat = 500
    static let minTitleWidth: CGFloat = 80

    struct RowData {
        let windowIndex: Int
        let title: String
        let numberView: NumberBubbleView
        let titleView: TitleBubbleView
    }

    private var rows: [RowData] = []
    private var titles: [String] = []
    private var onReorder: (([String]) -> Void)?

    var idealSize: NSSize {
        let count = CGFloat(max(rows.count, 1))
        let h = count * Self.rowHeight + (count - 1) * Self.rowSpacing + 2 * Self.padding
        let w = Self.padding + Self.numberSize + Self.horizontalGap + Self.maxTitleWidth + Self.padding
        return NSSize(width: w, height: h)
    }

    func configure(
        with windows: [(number: Int, title: String, windowID: CGWindowID, pid: pid_t)],
        onReorder: @escaping ([String]) -> Void
    ) {
        tearDown()
        self.onReorder = onReorder

        let sorted = windows.sorted { $0.number < $1.number }
        titles = sorted.map { $0.title }

        for (i, win) in sorted.enumerated() {
            let numberView = NumberBubbleView(number: win.number)
            let titleView = TitleBubbleView(title: win.title, rowIndex: i)
            titleView.dragDelegate = self

            addSubview(numberView)
            addSubview(titleView)

            rows.append(RowData(
                windowIndex: i,
                title: win.title,
                numberView: numberView,
                titleView: titleView
            ))
        }

        layoutRows(animated: false)
    }

    func tearDown() {
        for row in rows {
            row.numberView.removeFromSuperview()
            row.titleView.removeFromSuperview()
        }
        rows.removeAll()
        titles.removeAll()
        onReorder = nil
    }

    private func layoutRows(animated: Bool) {
        let size = idealSize
        let duration: TimeInterval = animated ? 0.2 : 0

        for (i, row) in rows.enumerated() {
            let rowY = size.height - Self.padding - Self.rowHeight - CGFloat(i) * (Self.rowHeight + Self.rowSpacing)

            let numberFrame = NSRect(
                x: Self.padding,
                y: rowY,
                width: Self.numberSize,
                height: Self.numberSize
            )

            let titleWidth = titleBubbleWidth(for: row.title)
            let titleFrame = NSRect(
                x: Self.padding + Self.numberSize + Self.horizontalGap,
                y: rowY,
                width: titleWidth,
                height: Self.rowHeight
            )

            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = duration
                    ctx.allowsImplicitAnimation = true
                    row.numberView.animator().frame = numberFrame
                    row.titleView.animator().frame = titleFrame
                }
            } else {
                row.numberView.frame = numberFrame
                row.titleView.frame = titleFrame
            }
        }
    }

    private func titleBubbleWidth(for title: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium)
        ]
        let textWidth = (title as NSString).size(withAttributes: attrs).width
        let width = textWidth + 32
        return min(max(width, Self.minTitleWidth), Self.maxTitleWidth)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        for row in rows {
            let localPoint = row.titleView.convert(point, from: self)
            if row.titleView.bounds.contains(localPoint) {
                return row.titleView
            }
        }
        return nil
    }

    // MARK: - Row position helpers for drag

    func rowSlotY(forIndex i: Int) -> CGFloat {
        let size = idealSize
        return size.height - Self.padding - Self.rowHeight - CGFloat(i) * (Self.rowHeight + Self.rowSpacing) + Self.rowHeight / 2
    }

    func nearestRow(forMidY midY: CGFloat, excludingRow: Int) -> Int? {
        var best = excludingRow
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in 0..<rows.count {
            let slotMidY = rowSlotY(forIndex: i)
            let dist = abs(midY - slotMidY)
            if dist < bestDist {
                bestDist = dist
                best = i
            }
        }
        return best != excludingRow ? best : nil
    }

    func performReorder(fromRow: Int, toRow: Int) {
        titles.swapAt(fromRow, toRow)

        let titleViewA = rows[fromRow].titleView
        let titleViewB = rows[toRow].titleView
        titleViewA.rowIndex = toRow
        titleViewB.rowIndex = fromRow

        rows[fromRow] = RowData(
            windowIndex: fromRow,
            title: titles[fromRow],
            numberView: rows[fromRow].numberView,
            titleView: titleViewB
        )
        rows[toRow] = RowData(
            windowIndex: toRow,
            title: titles[toRow],
            numberView: rows[toRow].numberView,
            titleView: titleViewA
        )

        layoutRows(animated: true)
        onReorder?(titles)
    }
}

// MARK: - Number Bubble
// NSVisualEffectView subclass — uses maskImage (not layer.cornerRadius) to preserve blur compositing.

class NumberBubbleView: NSVisualEffectView {

    private let label = NSTextField(labelWithString: "")
    private var lastMaskSize: NSSize = .zero

    init(number: Int) {
        super.init(frame: .zero)

        material = .popover
        state = .active
        blendingMode = .behindWindow
        appearance = NSAppearance(named: .darkAqua)

        label.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.stringValue = "\(number)"
        addSubview(label)

        shadow = {
            let s = NSShadow()
            s.shadowBlurRadius = 8
            s.shadowOffset = NSSize(width: 0, height: -2)
            s.shadowColor = NSColor.black.withAlphaComponent(0.3)
            return s
        }()
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateNumber(_ number: Int) {
        label.stringValue = "\(number)"
    }

    override func layout() {
        super.layout()
        if bounds.size != lastMaskSize && bounds.width > 0 {
            lastMaskSize = bounds.size
            maskImage = roundedMaskImage(size: bounds.size, cornerRadius: bounds.height / 2)
        }
        let textH = label.intrinsicContentSize.height
        label.frame = NSRect(x: 0, y: (bounds.height - textH) / 2, width: bounds.width, height: textH)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

// MARK: - Title Bubble

class TitleBubbleView: NSVisualEffectView {

    weak var dragDelegate: WindowOverlayContentView?
    var rowIndex: Int

    private let label = NSTextField(labelWithString: "")
    private var lastMaskSize: NSSize = .zero

    private var isDragging = false
    private var dragStartY: CGFloat = 0
    private var originalFrameOriginY: CGFloat = 0

    init(title: String, rowIndex: Int) {
        self.rowIndex = rowIndex
        super.init(frame: .zero)

        material = .popover
        state = .active
        blendingMode = .behindWindow
        appearance = NSAppearance(named: .darkAqua)

        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.alignment = .left
        label.lineBreakMode = .byTruncatingMiddle
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.stringValue = title
        label.maximumNumberOfLines = 1
        addSubview(label)

        shadow = {
            let s = NSShadow()
            s.shadowBlurRadius = 8
            s.shadowOffset = NSSize(width: 0, height: -2)
            s.shadowColor = NSColor.black.withAlphaComponent(0.3)
            return s
        }()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        if bounds.size != lastMaskSize && bounds.width > 0 {
            lastMaskSize = bounds.size
            maskImage = roundedMaskImage(size: bounds.size, cornerRadius: bounds.height / 2)
        }
        let textH = label.intrinsicContentSize.height
        label.frame = NSRect(x: 16, y: (bounds.height - textH) / 2, width: bounds.width - 32, height: textH)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if frame.contains(point) { return self }
        return nil
    }

    // MARK: - Drag handling

    override func mouseDown(with event: NSEvent) {
        guard let sv = superview else { return }
        let locationInSuperview = sv.convert(event.locationInWindow, from: nil)
        isDragging = true
        dragStartY = locationInSuperview.y
        originalFrameOriginY = frame.origin.y
        sv.addSubview(self)
        layer?.setAffineTransform(CGAffineTransform(scaleX: 1.05, y: 1.05))
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let sv = superview else { return }
        let locationInSuperview = sv.convert(event.locationInWindow, from: nil)
        let deltaY = locationInSuperview.y - dragStartY
        frame.origin.y = originalFrameOriginY + deltaY
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        layer?.setAffineTransform(.identity)

        if let targetRow = dragDelegate?.nearestRow(forMidY: frame.midY, excludingRow: rowIndex) {
            dragDelegate?.performReorder(fromRow: rowIndex, toRow: targetRow)
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                self.animator().frame.origin.y = originalFrameOriginY
            }
        }
    }
}
