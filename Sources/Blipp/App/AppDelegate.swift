import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate, NSViewToolTipOwner {
    private let prefs = Preferences()
    private lazy var monitor = SystemMonitor(prefs: prefs)

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var frameTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastIconKey: IconKey?
    private var panelOpenedAt: TimeInterval = 0
    private var latestPanelHeight: CGFloat = 0

    /// Everything that changes how the status item looks. Equal keys mean nothing to redraw.
    private struct IconKey: Equatable {
        var scene: BlippScene
        var style: IconStyle
        var accessory: MenuBarIcon.Accessory
        var bars: [Int]
        var title: String
        var frame: Int
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeft
            button.setAccessibilityLabel("Blipp")
            // The tooltip text is asked for only when the pointer hovers, so a changing
            // subtitle never forces the menu bar to refresh.
            button.addToolTip(button.bounds, owner: self, userData: nil)
            button.postsFrameChangedNotifications = true
            NotificationCenter.default.publisher(for: NSView.frameDidChangeNotification, object: button)
                .sink { [weak button, weak self] _ in
                    guard let button, let self else { return }
                    button.removeAllToolTips()
                    button.addToolTip(button.bounds, owner: self, userData: nil)
                }
                .store(in: &cancellables)
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        monitor.$mood
            .combineLatest(monitor.$snapshot)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.refreshStatusItem() }
            .store(in: &cancellables)

        prefs.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // objectWillChange fires before the new value is stored.
                DispatchQueue.main.async { self?.refreshStatusItem() }
            }
            .store(in: &cancellables)

        refreshStatusItem()

        // Developer aid: opens the panel after 2 s, expands and collapses both sections,
        // and closes it after 32 s (for measuring energy use and checking animations).
        if CommandLine.arguments.contains("--debug-panel-cycle") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.togglePopover() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 32) { [weak self] in self?.popover.performClose(nil) }
            for (delay, section) in [(4.0, "cpu"), (6.0, "cpu"), (8.0, "memory"), (10.0, "memory")] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    NotificationCenter.default.post(name: Notification.Name("BlippDebugToggle"), object: section)
                }
            }
        }
    }

    // MARK: Status item

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        let snapshot = monitor.snapshot
        let scene = monitor.mood.scene
        let animate = prefs.animateMenuBar
        let time = animate ? ProcessInfo.processInfo.systemUptime : MenuBarRenderer.stillTime

        var accessory = MenuBarIcon.Accessory.none
        if let battery = snapshot.battery {
            if battery.isCharging {
                accessory = .bolt
            } else if !battery.onAC && battery.percent < 20 {
                accessory = .lowBattery
            }
        }

        var bars: (cpu: Double, memory: Double)?
        var title = ""
        switch prefs.menuBarDisplay {
        case .blippOnly:
            break
        case .cpuPercent:
            title = Self.fixedWidthPercent(snapshot.cpuTotal)
        case .miniBars:
            bars = (snapshot.cpuTotal / 100, snapshot.memory.usedFraction)
        case .batteryPercent:
            if let battery = snapshot.battery { title = Self.fixedWidthPercent(Double(battery.percent)) }
        }

        let key = IconKey(
            scene: scene,
            style: prefs.iconStyle,
            accessory: accessory,
            bars: bars.map { [Int($0.cpu * 14), Int($0.memory * 14)] } ?? [],
            title: title,
            frame: MenuBarRenderer.frame(for: scene, time: time)
        )
        scheduleNextFrame(scene: scene, time: time, animate: animate)
        guard key != lastIconKey else { return }
        lastIconKey = key

        button.image = MenuBarIcon.image(scene: scene, style: prefs.iconStyle, accessory: accessory, bars: bars, time: time)

        if title.isEmpty {
            if !button.title.isEmpty { button.title = "" }
        } else {
            let attributed = NSAttributedString(
                string: " " + title,
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)]
            )
            if button.attributedTitle != attributed {
                button.attributedTitle = attributed
            }
        }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        "\(monitor.mood.title) – \(monitor.mood.subtitle)"
    }

    /// "9%", "42%" and "100%" all take the same width: the number is padded with figure spaces,
    /// which are exactly as wide as a digit, so neither Blipp nor the icons next to him move
    /// when the value gains or loses a digit.
    private static func fixedWidthPercent(_ value: Double) -> String {
        let digits = String(Int(min(100, max(0, value)).rounded()))
        return digits + "%" + String(repeating: "\u{2007}", count: max(0, 3 - digits.count))
    }

    /// Wakes up exactly when the icon's next animation frame is due (a blink, a sweat drop)
    /// instead of polling on a fixed timer. A calm Blipp costs two redraws every few seconds.
    private func scheduleNextFrame(scene: BlippScene, time: Double, animate: Bool) {
        guard animate else {
            frameTimer?.invalidate()
            frameTimer = nil
            return
        }
        let delay = max(0.02, MenuBarRenderer.nextFrameChange(for: scene, after: time) - time)
        // Already waiting for that moment? Keep the timer instead of churning a new one.
        if let existing = frameTimer, existing.isValid,
           abs(existing.fireDate.timeIntervalSinceNow - delay) < 0.01 {
            return
        }
        frameTimer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.frameTimer = nil
            self?.refreshStatusItem()
        }
        timer.tolerance = min(0.03, delay * 0.2)
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
            return
        }
        switch prefs.clickAction {
        case .showPanel: togglePopover()
        case .openActivityMonitor: openActivityMonitor()
        }
    }

    // MARK: Panel

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        // The panel is built fresh each time it opens and thrown away when it closes,
        // so nothing in it (animations, graphs, SwiftUI updates) runs while it's hidden.
        monitor.setPanelVisible(true)
        let panel = PanelView(
            monitor: monitor,
            prefs: prefs,
            actions: PanelActions(
                openActivityMonitor: { [weak self] in self?.openActivityMonitor() },
                openSettings: { [weak self] in self?.openSettings() },
                quit: { NSApp.terminate(nil) },
                heightChanged: { [weak self] height in
                    self?.latestPanelHeight = height
                    // Never resize from inside SwiftUI's layout pass; do it right after.
                    DispatchQueue.main.async { self?.resizePanel(to: height) }
                }
            )
        )
        // The SwiftUI view gets a fixed, generous height pinned to the top of a clipping
        // container, and only the container follows the content's height. SwiftUI's root never
        // changes size, so nothing gets re-centered (that re-centering made the panel shake).
        let hosting = NSHostingController(rootView: panel)
        hosting.sizingOptions = []
        let container = PanelContainerViewController(hosting: hosting)
        popover.contentViewController = container
        // Measure before showing, so the panel opens at its real size instead of growing into it.
        latestPanelHeight = 0
        container.layoutNow()
        popover.contentSize = NSSize(width: PanelContainerViewController.width, height: latestPanelHeight > 0 ? latestPanelHeight : 520)
        panelOpenedAt = ProcessInfo.processInfo.systemUptime

        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func resizePanel(to height: CGFloat) {
        let target = NSSize(width: PanelContainerViewController.width, height: height.rounded())
        guard target.height > 0, abs(popover.contentSize.height - target.height) >= 0.5 else { return }
        // Right after opening (or before), adjustments come from the first layout passes
        // (text wrapping, data arriving): apply them instantly rather than animating.
        let justOpened = ProcessInfo.processInfo.systemUptime - panelOpenedAt < 0.4
        guard popover.isShown, !justOpened else {
            popover.contentSize = target
            return
        }
        // The content is pinned to the top, so the window can glide to its new height
        // alongside SwiftUI's expand/collapse animation without anything shifting.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            popover.contentSize = target
        }
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
        monitor.setPanelVisible(false)
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Panel", action: #selector(menuShowPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open Activity Monitor", action: #selector(menuOpenActivityMonitor), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(menuOpenSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Blipp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuShowPanel() { togglePopover() }
    @objc private func menuOpenActivityMonitor() { openActivityMonitor() }
    @objc private func menuOpenSettings() { openSettings() }

    // MARK: Actions

    private func openActivityMonitor() {
        popover.performClose(nil)
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(prefs: prefs))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Blipp Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Let the settings window and its SwiftUI views go when they're closed.
        if (notification.object as? NSWindow) === settingsWindow {
            settingsWindow?.contentViewController = nil
            settingsWindow = nil
        }
    }
}

/// Holds the panel's SwiftUI view at a fixed size, pinned to the top, and clips it to whatever
/// height the popover currently has.
private final class PanelContainerViewController: NSViewController {
    static let width: CGFloat = 344
    /// Taller than the panel can ever get, so the SwiftUI view never needs to resize.
    static let canvasHeight: CGFloat = 1400

    private let hosting: NSViewController

    init(hosting: NSViewController) {
        self.hosting = hosting
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let container = FlippedView(frame: NSRect(x: 0, y: 0, width: Self.width, height: 400))
        container.clipsToBounds = true
        addChild(hosting)
        hosting.view.frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.canvasHeight)
        hosting.view.autoresizingMask = []
        container.addSubview(hosting.view)
        view = container
    }

    /// Runs a layout pass now, so the SwiftUI content reports its height before the panel shows.
    func layoutNow() {
        loadViewIfNeeded()
        hosting.view.layoutSubtreeIfNeeded()
    }

    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }
}

