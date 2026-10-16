import Cocoa
import ApplicationServices
import Carbon

// Accessibility does not expose a public window-number attribute. This SPI is
// the same bridge used by macOS window switchers to correlate AX and CG windows.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(
    _ element: AXUIElement,
    _ windowID: UnsafeMutablePointer<CGWindowID>
) -> AXError

// Swift marks this still-shipped Carbon routine unavailable because it was
// deprecated in 10.9. It remains the simplest way to obtain the PSN required
// by the window-specific SkyLight activation calls below.
@_silgen_name("GetProcessForPID")
private func LegacyGetProcessForPID(
    _ pid: pid_t,
    _ process: UnsafeMutablePointer<ProcessSerialNumber>
) -> OSStatus

@_silgen_name("_SLPSSetFrontProcessWithOptions")
private func SLPSSetFrontProcessWithOptions(
    _ process: UnsafePointer<ProcessSerialNumber>,
    _ windowID: CGWindowID,
    _ options: UInt32
) -> CGError

@_silgen_name("SLPSPostEventRecordTo")
private func SLPSPostEventRecordTo(
    _ process: UnsafePointer<ProcessSerialNumber>,
    _ bytes: UnsafeMutablePointer<UInt8>
) -> CGError

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ connection: Int32) -> Unmanaged<CFArray>?

@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(
    _ connection: Int32,
    _ mask: Int32,
    _ windowIDs: CFArray
) -> Unmanaged<CFArray>?

@_silgen_name("CGSManagedDisplayGetCurrentSpace")
private func CGSManagedDisplayGetCurrentSpace(_ connection: Int32, _ display: CFString) -> UInt64

struct DisplayDescriptor {
    let id: CGDirectDisplayID
    let uuid: String
    let frame: CGRect
}

struct NumberedDisplay {
    let number: Int
    let display: DisplayDescriptor
}

struct OffSpaceWindow {
    let windowID: CGWindowID
    let pid: pid_t
    let space: SpaceLocation
}

struct RoutableWindow {
    let windowID: CGWindowID
    let pid: pid_t
    let displayUUID: String
    let frame: CGRect
    let zOrder: Int
}

/// Where a Mission Control space lives: the managed-display identifier CGS
/// reports for it, the display UUID ISS switches on, and its zero-based
/// position in that display's space list (the index ISS swipes to).
struct SpaceLocation {
    let spaceID: UInt64
    let managedDisplayIdentifier: String
    let displayUUID: String
    let index: UInt32
}

enum Spaces {
    // kCGSAllSpacesMask: current and other spaces.
    private static let allSpacesMask: Int32 = 0x7

    static func locations() -> [UInt64: SpaceLocation] {
        let connection = CGSMainConnectionID()
        guard let displays = CGSCopyManagedDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]] else {
            return [:]
        }

        var result: [UInt64: SpaceLocation] = [:]
        for display in displays {
            guard let identifier = display["Display Identifier"] as? String,
                  let spaces = display["Spaces"] as? [[String: Any]] else {
                continue
            }
            // Without "Displays have separate Spaces", CGS reports one shared
            // "Main" display instead of a UUID.
            let displayUUID = identifier == "Main"
                ? DisplayGeometry.displayUUID(for: CGMainDisplayID()) ?? identifier
                : identifier
            for (index, space) in spaces.enumerated() {
                guard let spaceID = (space["id64"] as? NSNumber)?.uint64Value else { continue }
                result[spaceID] = SpaceLocation(
                    spaceID: spaceID,
                    managedDisplayIdentifier: identifier,
                    displayUUID: displayUUID,
                    index: UInt32(index)
                )
            }
        }
        return result
    }

    static func spaceID(forWindow windowID: CGWindowID) -> UInt64? {
        let windowIDs = [NSNumber(value: windowID)] as CFArray
        guard let spaces = CGSCopySpacesForWindows(CGSMainConnectionID(), allSpacesMask, windowIDs)?
            .takeRetainedValue() as? [NSNumber] else {
            return nil
        }
        return spaces.first?.uint64Value
    }

    static func isCurrent(_ location: SpaceLocation) -> Bool {
        CGSManagedDisplayGetCurrentSpace(
            CGSMainConnectionID(),
            location.managedDisplayIdentifier as CFString
        ) == location.spaceID
    }
}

enum DisplayGeometry {
    static func activeDisplays() -> [DisplayDescriptor] {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(displayIDs.count), &displayIDs, &count) == .success else {
            return []
        }

        return displayIDs.prefix(Int(count)).compactMap { displayID in
            guard let uuid = displayUUID(for: displayID) else { return nil }
            return DisplayDescriptor(id: displayID, uuid: uuid, frame: CGDisplayBounds(displayID))
        }
    }

    static func displayUUID(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) else {
            return nil
        }
        return string as String
    }

    static func display(for rect: CGRect, among displays: [DisplayDescriptor]) -> DisplayDescriptor? {
        guard !displays.isEmpty, !rect.isNull, !rect.isInfinite else { return nil }
        let center = CGPoint(x: rect.midX, y: rect.midY)

        let ranked = displays.map { display -> (display: DisplayDescriptor, area: CGFloat, containsCenter: Bool) in
            let intersection = rect.intersection(display.frame)
            let area = intersection.isNull ? 0 : max(0, intersection.width) * max(0, intersection.height)
            return (display, area, display.frame.contains(center))
        }.sorted { lhs, rhs in
            if lhs.area != rhs.area { return lhs.area > rhs.area }
            if lhs.containsCenter != rhs.containsCenter { return lhs.containsCenter }
            return lhs.display.uuid < rhs.display.uuid
        }

        guard let best = ranked.first, best.area > 0 else { return nil }
        return best.display
    }

    static func display(containing point: CGPoint, among displays: [DisplayDescriptor]) -> DisplayDescriptor? {
        displays.filter { $0.frame.contains(point) }.sorted { $0.uuid < $1.uuid }.first
    }

    static func numberedDisplays(
        displays: [DisplayDescriptor] = activeDisplays(),
        mainDisplayID: CGDirectDisplayID = CGMainDisplayID()
    ) -> [NumberedDisplay] {
        guard !displays.isEmpty else { return [] }

        let main = displays.first { $0.id == mainDisplayID }
        var remaining = displays.filter { $0.id != main?.id }
        remaining.sort { lhs, rhs in
            if lhs.frame.minX != rhs.frame.minX { return lhs.frame.minX < rhs.frame.minX }
            if lhs.frame.minY != rhs.frame.minY { return lhs.frame.minY < rhs.frame.minY }
            return lhs.uuid < rhs.uuid
        }

        var ordered: [DisplayDescriptor] = []
        if let main = main { ordered.append(main) }
        ordered.append(contentsOf: remaining)
        return ordered.enumerated().map { NumberedDisplay(number: $0.offset + 1, display: $0.element) }
    }
}

final class WindowRouter {
    // Off-screen helper surfaces (tooltips, drag images, offscreen renderers)
    // are layer-zero windows too; real document windows are never this small.
    private static let minimumOffSpaceWindowSide: CGFloat = 100

    // How long to wait for an instant space switch to land before giving up
    // on window-exact activation.
    private static let spaceSwitchTimeout: TimeInterval = 0.75
    private static let spaceSwitchPollInterval: TimeInterval = 0.016

    func snapshotFocusedDisplayUUID() -> String? {
        let displays = DisplayGeometry.activeDisplays()
        guard !displays.isEmpty else { return nil }

        if let focusedWindowFrame = systemFocusedWindowFrame(),
           let display = DisplayGeometry.display(for: focusedWindowFrame, among: displays) {
            return display.uuid
        }

        if let app = NSWorkspace.shared.frontmostApplication {
            if let focusedWindowFrame = focusedWindowFrame(for: app.processIdentifier),
               let display = DisplayGeometry.display(for: focusedWindowFrame, among: displays) {
                return display.uuid
            }

            // Some applications intermittently fail AXFocusedWindow queries.
            // Their first layer-zero CG window is the current frontmost window,
            // and is a better focus proxy than a pointer on another display.
            if let frontmostFrame = frontmostCGWindowFrame(for: app.processIdentifier),
               let display = DisplayGeometry.display(for: frontmostFrame, among: displays) {
                return display.uuid
            }
        }

        if let pointer = CGEvent(source: nil)?.location,
           let display = DisplayGeometry.display(containing: pointer, among: displays) {
            return display.uuid
        }

        return DisplayGeometry.numberedDisplays(displays: displays).first?.display.uuid
    }

    func eligibleWindows(forApplicationAt path: String) -> [RoutableWindow] {
        guard let app = runningApplication(forPath: path) else { return [] }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var windowsReference: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsReference
        ) == .success,
        let axWindows = windowsReference as? [AXUIElement] else {
            return []
        }

        var eligibleAXWindows: [CGWindowID: AXUIElement] = [:]
        for window in axWindows where isEligibleAXWindow(window) {
            var windowID: CGWindowID = 0
            if _AXUIElementGetWindow(window, &windowID) == .success, windowID != 0 {
                eligibleAXWindows[windowID] = window
            }
        }
        guard !eligibleAXWindows.isEmpty else { return [] }

        guard let cgWindows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        let displays = DisplayGeometry.activeDisplays()
        var result: [RoutableWindow] = []

        // CGWindowListCopyWindowInfo is front-to-back. Keeping this order gives
        // both per-display frontmost selection and a non-persisted global MRU.
        for (zOrder, info) in cgWindows.enumerated() {
            guard let ownerPID = numberValue(info[kCGWindowOwnerPID as String]).map({ pid_t($0.int32Value) }),
                  ownerPID == pid,
                  let layer = numberValue(info[kCGWindowLayer as String])?.intValue,
                  layer == 0,
                  let windowID = numberValue(info[kCGWindowNumber as String]).map({ CGWindowID($0.uint32Value) }),
                  eligibleAXWindows[windowID] != nil,
                  let frame = windowFrame(from: info),
                  let display = DisplayGeometry.display(for: frame, among: displays) else {
                continue
            }

            result.append(RoutableWindow(
                windowID: windowID,
                pid: pid,
                displayUUID: display.uuid,
                frame: frame,
                zOrder: zOrder
            ))
        }

        return result
    }

    /// The application's frontmost window that lives on a space not currently
    /// shown on any display. Accessibility only exposes windows on visible
    /// spaces, so these are found through Core Graphics and CGS instead.
    func offSpaceWindow(forApplicationAt path: String) -> OffSpaceWindow? {
        guard let app = runningApplication(forPath: path) else { return nil }
        let pid = app.processIdentifier

        guard let cgWindows = CGWindowListCopyWindowInfo(
            [.excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        let locations = Spaces.locations()
        for info in cgWindows {
            guard numberValue(info[kCGWindowOwnerPID as String])?.int32Value == pid,
                  numberValue(info[kCGWindowLayer as String])?.intValue == 0,
                  numberValue(info[kCGWindowIsOnscreen as String])?.boolValue != true,
                  let windowID = numberValue(info[kCGWindowNumber as String]).map({ CGWindowID($0.uint32Value) }),
                  let frame = windowFrame(from: info),
                  frame.width >= Self.minimumOffSpaceWindowSide,
                  frame.height >= Self.minimumOffSpaceWindowSide,
                  let spaceID = Spaces.spaceID(forWindow: windowID),
                  let location = locations[spaceID],
                  // Off-screen windows on a visible space are hidden or
                  // minimized; switching spaces would not reveal them.
                  !Spaces.isCurrent(location) else {
                continue
            }
            return OffSpaceWindow(windowID: windowID, pid: pid, space: location)
        }
        return nil
    }

    /// Switches instantly to the window's space, then activates exactly that
    /// window once the space is showing. Returns false if the switch could not
    /// be posted, so the caller can fall back to a normal launch.
    func routeToOffSpaceWindow(_ window: OffSpaceWindow, switchSpace: (SpaceLocation) -> Bool) -> Bool {
        guard switchSpace(window.space) else { return false }
        activateWhenSpaceIsCurrent(window, deadline: Date().addingTimeInterval(Self.spaceSwitchTimeout))
        return true
    }

    @discardableResult
    func routeApplication(at path: String, focusedDisplayUUID: String?) -> Bool {
        let windows = eligibleWindows(forApplicationAt: path)
        guard !windows.isEmpty else { return false }

        if let focusedDisplayUUID = focusedDisplayUUID,
           let focusedWindow = windows.first(where: { $0.displayUUID == focusedDisplayUUID }) {
            activate(focusedWindow)
            return true
        }

        let eligibleDisplays = Set(windows.map(\.displayUUID))
        if eligibleDisplays.count == 1, let onlyWindow = windows.first {
            activate(onlyWindow)
            return true
        }

        // The first entry is the selected application's foremost window in the
        // current Core Graphics z-order.
        if let mostRecentWindow = windows.first {
            activate(mostRecentWindow)
            return true
        }
        return false
    }

    func activate(_ window: RoutableWindow) {
        activate(windowID: window.windowID, pid: window.pid)
    }

    @discardableResult
    private func activate(windowID: CGWindowID, pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        if app.isHidden { app.unhide() }

        let appElement = AXUIElementCreateApplication(pid)
        guard let axWindow = axWindow(withID: windowID, in: appElement) else { return false }

        // The window-specific activation and key-window events establish focus
        // without toggling process-level AX attributes, which can raise every
        // sibling window in applications such as Firefox.
        activateExactWindow(windowID, of: app)
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        return true
    }

    private func activateWhenSpaceIsCurrent(_ window: OffSpaceWindow, deadline: Date) {
        // The window only becomes visible to Accessibility once its space is
        // showing, which lags the posted gesture by a few frames.
        if Spaces.isCurrent(window.space), activate(windowID: window.windowID, pid: window.pid) {
            return
        }
        guard Date() < deadline else {
            NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.spaceSwitchPollInterval) { [weak self] in
            self?.activateWhenSpaceIsCurrent(window, deadline: deadline)
        }
    }

    static func isApplicationBundle(path: String) -> Bool {
        URL(fileURLWithPath: path).pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }

    private func runningApplication(forPath path: String) -> NSRunningApplication? {
        let requestedURL = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        if let exact = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == requestedURL
        }) {
            return exact
        }

        guard let bundleID = Bundle(url: requestedURL)?.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    private func focusedWindowFrame(for pid: pid_t) -> CGRect? {
        let appElement = AXUIElementCreateApplication(pid)
        return focusedWindowFrame(in: appElement)
    }

    private func systemFocusedWindowFrame() -> CGRect? {
        Self.systemFocusedWindow().flatMap(Self.axFrame(of:))
    }

    private func focusedWindowFrame(in appElement: AXUIElement) -> CGRect? {
        Self.focusedWindow(in: appElement).flatMap(Self.axFrame(of:))
    }

    static func systemFocusedWindow() -> AXUIElement? {
        let systemElement = AXUIElementCreateSystemWide()
        var applicationReference: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemElement,
            kAXFocusedApplicationAttribute as CFString,
            &applicationReference
        ) == .success,
        let applicationElement = applicationReference as! AXUIElement? else {
            return nil
        }
        return focusedWindow(in: applicationElement)
    }

    private static func focusedWindow(in appElement: AXUIElement) -> AXUIElement? {
        var focusedReference: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedReference
        ) == .success else {
            return nil
        }
        return focusedReference as! AXUIElement?
    }

    private func frontmostCGWindowFrame(for pid: pid_t) -> CGRect? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for info in windows {
            guard numberValue(info[kCGWindowOwnerPID as String])?.int32Value == pid,
                  numberValue(info[kCGWindowLayer as String])?.intValue == 0 else {
                continue
            }
            if let frame = windowFrame(from: info) { return frame }
        }
        return nil
    }

    static func axFrame(of window: AXUIElement) -> CGRect? {
        var positionReference: CFTypeRef?
        var sizeReference: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionReference) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeReference) == .success,
              let positionValue = positionReference as! AXValue?,
              let sizeValue = sizeReference as! AXValue? else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func isEligibleAXWindow(_ window: AXUIElement) -> Bool {
        var subroleReference: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXSubroleAttribute as CFString,
            &subroleReference
        ) == .success,
        let subrole = subroleReference as? String,
        subrole == kAXStandardWindowSubrole as String else {
            return false
        }

        var minimizedReference: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            &minimizedReference
        ) == .success,
        let minimized = minimizedReference as? Bool,
        minimized {
            return false
        }
        return true
    }

    private func axWindow(withID soughtID: CGWindowID, in appElement: AXUIElement) -> AXUIElement? {
        var windowsReference: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsReference
        ) == .success,
        let windows = windowsReference as? [AXUIElement] else {
            return nil
        }

        return windows.first { window in
            var windowID: CGWindowID = 0
            return _AXUIElementGetWindow(window, &windowID) == .success && windowID == soughtID
        }
    }

    private func activateExactWindow(_ windowID: CGWindowID, of app: NSRunningApplication) {
        var process = ProcessSerialNumber()
        guard LegacyGetProcessForPID(app.processIdentifier, &process) == noErr else { return }

        // kCPSUserGenerated. Unlike SetFrontProcessWithOptions, this private
        // SkyLight variant names the exact window and does not raise siblings.
        _ = SLPSSetFrontProcessWithOptions(&process, windowID, 0x200)
        makeKeyWindow(windowID, of: &process)
    }

    private func makeKeyWindow(
        _ windowID: CGWindowID,
        of process: inout ProcessSerialNumber
    ) {
        var event = [UInt8](repeating: 0, count: 0xf8)
        event[0x04] = 0xf8
        event[0x3a] = 0x10
        event.replaceSubrange(0x20..<0x30, with: repeatElement(0xff, count: 0x10))

        withUnsafeBytes(of: windowID) { windowBytes in
            event.replaceSubrange(0x3c..<0x40, with: windowBytes)
        }

        event.withUnsafeMutableBufferPointer { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            bytes[0x08] = 0x01
            _ = SLPSPostEventRecordTo(&process, baseAddress)
            bytes[0x08] = 0x02
            _ = SLPSPostEventRecordTo(&process, baseAddress)
        }
    }

    private func windowFrame(from info: [String: Any]) -> CGRect? {
        guard let rawBounds = info[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return CGRect(dictionaryRepresentation: rawBounds as CFDictionary)
    }

    private func numberValue(_ value: Any?) -> NSNumber? {
        value as? NSNumber
    }
}
