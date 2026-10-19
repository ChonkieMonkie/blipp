import AppKit
import Combine
import CSensors
import Foundation
import IOKit.ps

/// Samples the system on a background queue and publishes snapshots, graphs and Blipp's mood.
///
/// Work is scaled to what's on screen: while the panel is closed only what Blipp himself
/// needs is measured at full rate, and nothing runs while the displays are asleep.
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var graphs = Graphs()
    @Published private(set) var mood = Mood.initial

    let coreLayout = CoreLayout.current

    private let prefs: Preferences
    private let queue = DispatchQueue(label: "io.github.chonkiemonkie.blipp.sampler", qos: .utility)
    private var cancellables = Set<AnyCancellable>()
    private var powerSource: CFRunLoopSource?

    // Only touched on `queue`.
    private var timer: DispatchSourceTimer?
    private var interval: TimeInterval = 1
    private var paused = false
    private var panelVisible = false
    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let battery = BatterySampler()
    private let disk = DiskSampler()
    private let processes = ProcessSampler()
    private lazy var network = NetworkSampler(queue: queue)
    private var cpuSeries = Series(maxAge: 30)
    private var temperatureSeries = Series()
    private var networkSeries = Series()
    private var diskSeries = Series()
    private var memorySeries = Series()
    private var lastProcessScan: TimeInterval = -.infinity
    private var topProcesses: [ProcessUsage] = []
    private var lastBatteryRead: TimeInterval = -.infinity
    private var batteryInfo: BatteryInfo?
    private var batteryDirty = true
    private var span: TimeInterval = 60
    /// Only for rendering README pictures: shown instead of the real process list.
    private var exampleProcesses: [ProcessUsage]?

    // Only touched on the main thread.
    private let moodEngine = MoodEngine()
    private var lastMoodUpdate: TimeInterval = -.infinity
    private var smoothedCPU: Double = 0

    /// With the panel open: the whole set of die sensors is refreshed every ~4 samples.
    private enum Visible {
        static let temperatureReads: Int32 = 6
        static let spaceInterval: TimeInterval = 30
    }

    /// While the panel is closed temperature only feeds graph history, and processes,
    /// battery details and free space only feed text, so they refresh more slowly.
    private enum Closed {
        static let temperatureReads: Int32 = 2
        static let processInterval: TimeInterval = 5
        static let batteryInterval: TimeInterval = 15
        static let spaceInterval: TimeInterval = 60
    }

    init(prefs: Preferences) {
        self.prefs = prefs

        prefs.$graphInterval
            .removeDuplicates()
            .sink { [weak self] interval in
                self?.queue.async {
                    self?.interval = interval
                    self?.reschedule()
                }
            }
            .store(in: &cancellables)

        prefs.$graphSpan
            .removeDuplicates()
            .sink { [weak self] span in
                self?.queue.async {
                    guard let self else { return }
                    self.span = span
                    if self.panelVisible { self.publishGraphs() }
                }
            }
            .store(in: &cancellables)

        prefs.$randomizeVariants
            .sink { [weak self] randomize in self?.moodEngine.randomize = randomize }
            .store(in: &cancellables)

        observePowerSource()
        observeScreens()
    }

    deinit {
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode)
        }
    }

    /// Shows a fixed list instead of this Mac's processes. Used when rendering README pictures,
    /// so nobody's own apps end up in them; the app itself never calls this.
    func useExampleProcesses(_ processes: [ProcessUsage]) {
        queue.async { [weak self] in self?.exampleProcesses = processes }
    }

    /// The panel shows graphs, processes and live battery details, so it gets them at full rate.
    func setPanelVisible(_ visible: Bool) {
        queue.async { [weak self] in
            guard let self, self.panelVisible != visible else { return }
            self.panelVisible = visible
            if visible {
                self.batteryDirty = true
                self.lastProcessScan = -.infinity
                self.disk.refreshSpaceSoon()
                self.publishGraphs()
                self.tick(forceMood: false)
            }
        }
    }

    // MARK: Scheduling

    private func reschedule() {
        timer?.cancel()
        timer = nil
        guard !paused else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // Generous leeway lets macOS batch our wake-ups with others; samples are timestamped anyway.
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(Int(interval * 250)))
        timer.setEventHandler { [weak self] in self?.tick(forceMood: false) }
        timer.resume()
        self.timer = timer
    }

    private func setPaused(_ paused: Bool) {
        queue.async { [weak self] in
            guard let self, self.paused != paused else { return }
            self.paused = paused
            if !paused { self.batteryDirty = true }
            self.reschedule()
        }
    }

    private func observeScreens() {
        let center = NSWorkspace.shared.notificationCenter
        let pause: [Notification.Name] = [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification]
        let resume: [Notification.Name] = [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification]
        for name in pause {
            center.publisher(for: name)
                .sink { [weak self] _ in self?.setPaused(true) }
                .store(in: &cancellables)
        }
        for name in resume {
            center.publisher(for: name)
                .sink { [weak self] _ in self?.setPaused(false) }
                .store(in: &cancellables)
        }
    }

    /// macOS tells us when a charger is plugged in or the level changes, so Blipp reacts
    /// right away without polling the battery every second.
    private func observePowerSource() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<SystemMonitor>.fromOpaque(context).takeUnretainedValue().powerSourceChanged()
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSource = source
    }

    private func powerSourceChanged() {
        queue.async { [weak self] in
            guard let self, !self.paused else { return }
            self.batteryDirty = true
            self.tick(forceMood: true)
        }
    }

    // MARK: Sampling

    private func tick(forceMood: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        var next = Snapshot()

        let load = cpu.sample()
        next.cpuTotal = load.total
        next.cpuCores = load.cores
        cpuSeries.append(load.total, at: now)

        next.memory = memory.sample()
        next.thermal = ProcessInfo.processInfo.thermalState

        let batteryInterval = panelVisible ? 0 : Closed.batteryInterval
        if batteryDirty || now - lastBatteryRead >= batteryInterval {
            batteryInfo = battery.sample()
            lastBatteryRead = now
            batteryDirty = false
        }
        next.battery = batteryInfo

        let temperature = blipp_cpu_temperature(panelVisible ? Visible.temperatureReads : Closed.temperatureReads)
        next.temperature = temperature > 0 ? temperature : nil

        let traffic = network.sample(now: now)
        next.networkDown = traffic.down
        next.networkUp = traffic.up
        next.online = network.online

        let io = disk.sample(now: now, spaceInterval: panelVisible ? Visible.spaceInterval : Closed.spaceInterval)
        next.diskRead = io.read
        next.diskWrite = io.write
        next.diskFree = io.free
        next.diskTotal = io.total

        // Scanning every process is the most expensive part: at most once a second with the
        // panel open, every few seconds otherwise (it only feeds text).
        let processInterval = panelVisible ? max(0.95, interval - 0.05) : Closed.processInterval
        if now - lastProcessScan >= processInterval {
            topProcesses = processes.sample(now: now)
            lastProcessScan = now
        }
        next.topProcesses = exampleProcesses ?? topProcesses

        if let celsius = next.temperature {
            temperatureSeries.append(celsius, at: now)
        }
        networkSeries.append(next.networkDown, at: now)
        diskSeries.append(next.diskIO, at: now)
        memorySeries.append(next.memory.used, at: now)

        let smoothed = cpuSeries.average(since: now - 5) ?? load.total
        let graphs = panelVisible ? makeGraphs(now: now) : nil

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.snapshot != next { self.snapshot = next }
            if let graphs, self.graphs != graphs { self.graphs = graphs }
            self.smoothedCPU = smoothed
            self.updateMood(now: now, force: forceMood)
        }
    }

    private func makeGraphs(now: TimeInterval) -> Graphs {
        Graphs(
            temperature: temperatureSeries.points(span: span, now: now),
            networkDown: networkSeries.points(span: span, now: now),
            diskIO: diskSeries.points(span: span, now: now),
            memoryUsed: memorySeries.points(span: span, now: now)
        )
    }

    private func publishGraphs() {
        let graphs = makeGraphs(now: ProcessInfo.processInfo.systemUptime)
        DispatchQueue.main.async { [weak self] in self?.graphs = graphs }
    }

    private func updateMood(now: TimeInterval, force: Bool) {
        guard force || now - lastMoodUpdate >= prefs.moodInterval - 0.1 else { return }
        lastMoodUpdate = now
        let next = moodEngine.mood(for: snapshot, smoothedCPU: smoothedCPU)
        if next != mood {
            mood = next
        }
    }
}
