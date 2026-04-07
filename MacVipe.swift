import AppKit
import CoreGraphics
import ServiceManagement

// MARK: - Constants

let exitHoldDuration: TimeInterval = 2.0
let overlayAlpha: CGFloat = 1.0
let timerInterval: TimeInterval = 0.03
let escKeyCode: Int64 = 53

// MARK: - OverlayView

class OverlayView: NSView {
    var escProgress: CGFloat = 0.0

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.clear.setFill()
        dirtyRect.fill()

        let centerX = bounds.midX
        let centerY = bounds.midY

        // "Cleaning Mode" title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 28, weight: .ultraLight),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7)
        ]
        let title = NSAttributedString(string: "Cleaning Mode", attributes: titleAttrs)
        let titleSize = title.size()
        title.draw(at: NSPoint(x: centerX - titleSize.width / 2, y: centerY + 20))

        // Subtitle
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .light),
            .foregroundColor: NSColor.white.withAlphaComponent(0.4)
        ]
        let subtitle = NSAttributedString(string: "Hold ESC for 2s to exit", attributes: subAttrs)
        let subSize = subtitle.size()
        subtitle.draw(at: NSPoint(x: centerX - subSize.width / 2, y: centerY - 15))

        // Progress ring
        let ringCenter = NSPoint(x: centerX, y: centerY - 55)
        let ringRadius: CGFloat = 18

        // Background ring
        let bgRing = NSBezierPath()
        bgRing.appendArc(
            withCenter: ringCenter,
            radius: ringRadius,
            startAngle: 0,
            endAngle: 360
        )
        NSColor.white.withAlphaComponent(0.15).setStroke()
        bgRing.lineWidth = 3
        bgRing.stroke()

        // Progress arc
        if escProgress > 0 {
            let progressRing = NSBezierPath()
            let startAngle: CGFloat = 90
            let endAngle: CGFloat = 90 - (escProgress * 360)
            progressRing.appendArc(
                withCenter: ringCenter,
                radius: ringRadius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: true
            )
            NSColor.white.withAlphaComponent(0.8).setStroke()
            progressRing.lineWidth = 3
            progressRing.lineCapStyle = .round
            progressRing.stroke()
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var overlayWindows: [NSWindow] = []
    var overlayViews: [OverlayView] = []
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var escPressedAt: Date?
    var escTimer: Timer?

    var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.showWelcomePopover()
        }
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "CleaningMode")
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Start Cleaning", action: #selector(startCleaningClicked), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())

        let launchItem = NSMenuItem(title: "Open on Startup", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit CleaningMode", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                // silently fail
            }
        }
        // Update checkbox state
        if let menu = statusItem.menu,
           let item = menu.item(withTitle: "Open on Startup") {
            item.state = isLaunchAtLoginEnabled() ? .on : .off
        }
    }

    func showWelcomePopover() {
        guard let button = statusItem.button else { return }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let viewController = NSViewController()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 70))

        let title = NSTextField(labelWithString: "CleaningMode is ready!")
        title.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor
        title.frame = NSRect(x: 16, y: 36, width: 190, height: 20)

        let subtitle = NSTextField(labelWithString: "Click this icon to start cleaning.")
        subtitle.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 16, y: 14, width: 190, height: 18)

        view.addSubview(title)
        view.addSubview(subtitle)
        viewController.view = view

        popover.contentViewController = viewController
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover

        // Auto-dismiss after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.popover?.close()
            self?.popover = nil
        }
    }

    @objc func startCleaningClicked() {
        if checkAccessibility() {
            startCleaningMode()
        } else {
            showAccessibilityAlert()
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    func checkAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func startCleaningMode() {
        createOverlayWindows()
        _ = installEventTap()
        NSCursor.hide()
    }

    func createOverlayWindows() {
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )

            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            window.backgroundColor = NSColor.black.withAlphaComponent(overlayAlpha)
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let overlayView = OverlayView(frame: screen.frame)
            window.contentView = overlayView

            window.orderFrontRegardless()
            window.makeKey()

            overlayWindows.append(window)
            overlayViews.append(overlayView)
        }
    }

    func installEventTap() -> Bool {
        var eventMask: CGEventMask = 0
        let eventTypes: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged,
            .scrollWheel,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged
        ]
        for t in eventTypes {
            eventMask |= (1 << t.rawValue)
        }

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: refcon
        ) else {
            return false
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), self.runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        return true
    }

    func onEscDown() {
        if escPressedAt == nil {
            escPressedAt = Date()
            escTimer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] _ in
                self?.updateEscProgress()
            }
        }
    }

    func onEscUp() {
        escPressedAt = nil
        escTimer?.invalidate()
        escTimer = nil
        updateProgress(0)
    }

    func updateEscProgress() {
        guard let pressedAt = escPressedAt else { return }
        let elapsed = Date().timeIntervalSince(pressedAt)
        let progress = CGFloat(min(elapsed / exitHoldDuration, 1.0))
        updateProgress(progress)

        if elapsed >= exitHoldDuration {
            stopCleaningMode()
        }
    }

    func updateProgress(_ progress: CGFloat) {
        for view in overlayViews {
            view.escProgress = progress
            view.needsDisplay = true
        }
    }

    func stopCleaningMode() {
        escTimer?.invalidate()
        escTimer = nil

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        overlayViews.removeAll()

        NSCursor.unhide()
    }

    func showAccessibilityAlert() {
        NSApp.setActivationPolicy(.regular)
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "CleaningMode needs Accessibility access to block keyboard and trackpad input.\n\nGrant access in System Settings > Privacy & Security > Accessibility, then try again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Event Tap Callback

func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo = userInfo {
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = delegate.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard let userInfo = userInfo else {
        return nil
    }

    let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .keyDown || type == .keyUp {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == escKeyCode {
            DispatchQueue.main.async {
                if type == .keyDown {
                    delegate.onEscDown()
                } else {
                    delegate.onEscUp()
                }
            }
        }
    }

    return nil
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
