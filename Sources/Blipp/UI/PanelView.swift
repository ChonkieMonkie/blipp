// Blipp, a menu bar sidekick that shows how your Mac is doing.
// Copyright (C) 2026  Anton Gedda
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import SwiftUI

struct PanelActions {
    var openActivityMonitor: () -> Void
    var openSettings: () -> Void
    var quit: () -> Void
    /// Called with the content's height on every layout pass, including each frame of an
    /// expand/collapse animation, so the popover can follow it exactly.
    var heightChanged: (CGFloat) -> Void = { _ in }
}

private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The window that drops down from the menu bar.
struct PanelView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var prefs: Preferences
    let actions: PanelActions

    // The Command Line Tools ship without SwiftUI's macro plugin, so @State is off limits;
    // a small observable object keeps the panel's own UI state instead.
    @StateObject private var ui: PanelUIState

    init(monitor: SystemMonitor, prefs: Preferences, actions: PanelActions, startExpanded: Bool = false) {
        self.monitor = monitor
        self.prefs = prefs
        self.actions = actions
        _ui = StateObject(wrappedValue: PanelUIState(expanded: startExpanded))
    }

    var body: some View {
        let snapshot = monitor.snapshot
        VStack(alignment: .leading, spacing: 14) {
            header
            VStack(alignment: .leading, spacing: 12) {
                cpuSection(snapshot)
                memorySection(snapshot)
                if let battery = snapshot.battery {
                    BatterySection(battery: battery)
                }
                tiles(snapshot)
            }
            topProcesses(snapshot)
            footer
        }
        .padding(16)
        .frame(width: 344)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
        })
        .onPreferenceChange(PanelHeightKey.self) { height in actions.heightChanged(height) }
        // Pin the content to the top so nothing above an expanding section ever moves.
        .frame(maxHeight: .infinity, alignment: .top)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BlippDebugToggle"))) { note in
            withAnimation(.easeInOut(duration: 0.25)) {
                if note.object as? String == "cpu" { ui.cpuExpanded.toggle() } else { ui.memoryExpanded.toggle() }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: monitor.mood.scene.color).opacity(0.28))
                BlippView(scene: monitor.mood.scene, size: 50)
                    .offset(y: -2)
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 3) {
                Text(monitor.mood.title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                Text(monitor.mood.subtitle)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: CPU

    private func cpuSection(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ExpandHeader(
                icon: "cpu", title: "CPU", detail: nil,
                value: Format.percent(s.cpuTotal),
                toggleLabel: ui.cpuExpanded ? "Hide cores" : "Per core",
                expanded: $ui.cpuExpanded
            )
            MeterBar(fraction: s.cpuTotal / 100, color: HeatScale.cpu.color(at: s.cpuTotal))
            if ui.cpuExpanded {
                CoreGrid(cores: s.cpuCores, layout: monitor.coreLayout)
                    .transition(.opacity)
            }
        }
    }

    // MARK: Memory

    private func memorySection(_ s: Snapshot) -> some View {
        let memory = s.memory
        let pressureColor: Color = {
            switch memory.pressure {
            case .normal: return Color(hex: HeatScale.green)
            case .warning: return Color(hex: HeatScale.yellow)
            case .critical: return Color(hex: HeatScale.red)
            }
        }()
        return VStack(alignment: .leading, spacing: 6) {
            ExpandHeader(
                icon: "memorychip", title: "Memory", detail: "· pressure \(memory.pressure.title)",
                value: "\(gigabytes(memory.used)) / \(gigabytes(memory.total, decimals: 0)) GB",
                toggleLabel: nil,
                expanded: $ui.memoryExpanded
            )
            MeterBar(fraction: memory.usedFraction, color: pressureColor)
            if ui.memoryExpanded {
                MemoryDetail(memory: memory, points: monitor.graphs.memoryUsed, span: prefs.graphSpan)
                    .transition(.opacity)
            }
        }
    }

    private func gigabytes(_ bytes: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", bytes / 1_073_741_824)
    }

    // MARK: Tiles

    private func tiles(_ s: Snapshot) -> some View {
        let graphs = monitor.graphs
        let networkPeak = max(graphs.networkDown.map(\.value).max() ?? 0, 1_000_000) * 1.15
        let diskPeak = max(graphs.diskIO.map(\.value).max() ?? 0, 10_000_000) * 1.15
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                GraphTile(
                    title: "Temperature",
                    value: s.temperature.map { "\(Int($0.rounded())) °C" } ?? s.thermal.title,
                    points: graphs.temperature, range: 20...100, scale: .temperature
                )
                .help("Thermal state: \(s.thermal.title)")
                GraphTile(
                    title: "Network ↓",
                    value: Format.rate(s.networkDown),
                    points: graphs.networkDown, range: 0...networkPeak, scale: .network
                )
                .help("Upload: \(Format.rate(s.networkUp))")
                GraphTile(
                    title: "Disk · \(Format.diskSpace(s.diskFree))",
                    value: Format.rate(s.diskIO),
                    points: graphs.diskIO, range: 0...diskPeak, scale: .disk
                )
                .help("Read \(Format.rate(s.diskRead)) · Write \(Format.rate(s.diskWrite)) · \(Format.diskSpace(s.diskFree)) free")
            }
            Text("Graphs show the last \(Preferences.spanTitle(prefs.graphSpan, short: false)).")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Processes

    private static let processRows = 3

    private func topProcesses(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider()
                .padding(.bottom, 5)
            Text("TOP CPU RIGHT NOW")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            // Always three rows tall, so the panel's bottom never jumps when fewer
            // processes are busy (or before the first measurement is in).
            ForEach(0..<Self.processRows, id: \.self) { index in
                let process = index < s.topProcesses.count ? s.topProcesses[index] : nil
                HStack {
                    if let process {
                        Text(process.name)
                            .lineLimit(1)
                        Spacer()
                        Text(Format.processPercent(process.cpu))
                            .fontWeight(.bold)
                            .monospacedDigit()
                    } else {
                        Text(index == 0 ? "Measuring…" : " ")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .font(.system(size: 13, design: .rounded))
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: actions.openActivityMonitor) {
                Text("Open Activity Monitor")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(action: actions.openSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("Settings")
            .accessibilityLabel("Settings")

            Button(action: actions.quit) {
                Image(systemName: "power")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("Quit Blipp")
            .accessibilityLabel("Quit Blipp")
        }
    }
}

// MARK: - Pieces

final class PanelUIState: ObservableObject {
    @Published var cpuExpanded: Bool
    @Published var memoryExpanded: Bool

    init(expanded: Bool) {
        cpuExpanded = expanded
        memoryExpanded = expanded
    }
}

private struct ExpandHeader: View {
    let icon: String
    let title: String
    let detail: String?
    let value: String
    let toggleLabel: String?
    @Binding var expanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(title).fontWeight(.bold)
                if let detail {
                    Text(detail).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 3) {
                    if let toggleLabel {
                        Text(toggleLabel)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(value)
                    .fontWeight(.heavy)
                    .monospacedDigit()
            }
            .font(.system(size: 13, design: .rounded))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value)")
        .accessibilityHint(expanded ? "Hides details" : "Shows details")
    }
}

struct MeterBar: View {
    let fraction: Double
    let color: Color
    var shimmer = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * min(1, max(0, fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(color)
                    .frame(width: width)
                    .overlay {
                        if shimmer {
                            ShimmerOverlay()
                                .clipShape(Capsule())
                        }
                    }
            }
        }
        .frame(height: 6)
    }
}

/// A light band sweeping across the battery bar while charging. It's a Core Animation
/// animation, so the window server runs it and Blipp does no work per frame.
private struct ShimmerOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> ShimmerView { ShimmerView() }
    func updateNSView(_ view: ShimmerView, context: Context) {}
}

private final class ShimmerView: NSView {
    private let band = CAGradientLayer()
    private let bandWidth: CGFloat = 40

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        band.colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.withAlphaComponent(0.6).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(band)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        band.frame = CGRect(x: -bandWidth, y: 0, width: bandWidth, height: bounds.height)
        CATransaction.commit()

        band.removeAnimation(forKey: "sweep")
        guard bounds.width > 0, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = -bandWidth / 2
        sweep.toValue = bounds.width + bandWidth / 2
        sweep.duration = 1.6
        sweep.repeatCount = .infinity
        band.add(sweep, forKey: "sweep")
    }
}

private struct CoreGrid: View {
    let cores: [Double]
    let layout: CoreLayout

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if layout.efficiency > 0, layout.performance > 0, layout.efficiency + layout.performance == cores.count {
                // Apple Silicon lists the efficiency cores first.
                group("Performance", Array(cores[layout.efficiency...]), prefix: "Performance core")
                Divider()
                group("Efficiency", Array(cores[..<layout.efficiency]), prefix: "Efficiency core")
            } else {
                group("Cores", cores, prefix: "Core")
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .modifier(CardStyle())
    }

    private func group(_ title: String, _ values: [Double], prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 2) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.1))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(HeatScale.cpu.color(at: value))
                                .frame(height: max(3, 40 * value / 100))
                        }
                        .frame(width: 14, height: 40)
                        Text("\(Int(value.rounded()))")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 20)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(prefix) \(index + 1): \(Int(value.rounded())) percent")
                }
            }
        }
    }
}

private struct MemoryDetail: View {
    let memory: MemoryInfo
    let points: [GraphPoint]
    let span: Double

    private struct Part: Identifiable {
        let name: String
        let bytes: Double
        let color: Color
        var dashed = false
        var id: String { name }
    }

    var body: some View {
        let gigabytes = memory.total
        let parts = [
            Part(name: "Apps", bytes: memory.app, color: Color(hex: 0x2F6FEB)),
            Part(name: "Wired", bytes: memory.wired, color: Color(hex: 0xF59E0B)),
            Part(name: "Compressed", bytes: memory.compressed, color: Color(hex: 0x9B6CF0)),
            Part(name: "Cached", bytes: memory.cached, color: Color(hex: 0xBFD3F5)),
        ]
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("USED · LAST \(Preferences.spanTitle(span).uppercased())")
                Spacer()
                Text(Format.bytes(gigabytes))
            }
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(.secondary)

            Sparkline(points: points, range: 0...max(gigabytes, 1), scale: memoryScale)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))

            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ForEach(parts) { part in
                        Rectangle()
                            .fill(part.color)
                            .frame(width: proxy.size.width * part.bytes / max(gigabytes, 1))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 10)
            .background(Color.primary.opacity(0.1))
            .clipShape(Capsule())
            .accessibilityHidden(true)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                GridRow {
                    legend(parts[0])
                    legend(parts[1])
                }
                GridRow {
                    legend(parts[2])
                    legend(parts[3])
                }
                GridRow {
                    legend(Part(name: "Swap", bytes: memory.swapUsed, color: .secondary, dashed: true))
                    legend(Part(name: "Free", bytes: memory.free, color: Color.primary.opacity(0.15)))
                }
            }
        }
        .padding(10)
        .modifier(CardStyle())
    }

    private var memoryScale: HeatScale {
        let total = max(memory.total, 1)
        return HeatScale([
            (total * 0.5, HeatScale.green), (total * 0.7, HeatScale.yellow),
            (total * 0.85, HeatScale.orange), (total * 0.97, HeatScale.red),
        ])
    }

    private func legend(_ part: Part) -> some View {
        HStack(spacing: 6) {
            Group {
                if part.dashed {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(part.color, style: StrokeStyle(lineWidth: 1.5, dash: [2, 1.5]))
                } else {
                    RoundedRectangle(cornerRadius: 2).fill(part.color)
                }
            }
            .frame(width: 9, height: 9)
            Text(part.name)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)
            Spacer(minLength: 2)
            Text(Format.bytes(part.bytes))
                .fontWeight(.heavy)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .font(.system(size: 12, design: .rounded))
        .frame(maxWidth: .infinity)
    }
}

private struct BatterySection: View {
    let battery: BatteryInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: iconName)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text("Battery").fontWeight(.bold)
                Text("· \(status)").foregroundStyle(.secondary)
                Spacer()
                Text("\(battery.percent)%")
                    .fontWeight(.heavy)
                    .monospacedDigit()
            }
            .font(.system(size: 13, design: .rounded))

            MeterBar(fraction: Double(battery.percent) / 100, color: barColor, shimmer: battery.isCharging)

            if let detail {
                HStack(spacing: 5) {
                    if battery.isCharging {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(Color(hex: HeatScale.green))
                    }
                    Text(detail)
                    Spacer()
                    if let time = timeText {
                        Text(time)
                    }
                }
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var iconName: String {
        if battery.isCharging { return "battery.100percent.bolt" }
        switch battery.percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var status: String {
        if battery.isCharging { return "charging" }
        if battery.onAC { return battery.percent >= 99 ? "charged" : "holding at limit" }
        return "on battery"
    }

    private var barColor: Color {
        switch battery.percent {
        case ..<10: return Color(hex: HeatScale.red)
        case ..<20: return Color(hex: HeatScale.orange)
        default: return Color(hex: HeatScale.green)
        }
    }

    private var detail: String? {
        if battery.isCharging, let watts = battery.watts, watts > 0.5 {
            return "\(Int(watts.rounded())) W into the battery"
        }
        if battery.onAC, let adapter = battery.adapterWatts {
            return "\(adapter) W adapter connected"
        }
        if !battery.onAC, let watts = battery.watts, watts < -0.5 {
            return "Using \(Int((-watts).rounded())) W"
        }
        return timeText == nil ? nil : ""
    }

    private var timeText: String? {
        if battery.isCharging, let minutes = battery.minutesToFull {
            return "full in \(Format.duration(minutes: minutes))"
        }
        if !battery.onAC, let minutes = battery.minutesToEmpty {
            return "\(Format.duration(minutes: minutes)) left"
        }
        return nil
    }
}

private struct GraphTile: View {
    let title: String
    let value: String
    let points: [GraphPoint]
    let range: ClosedRange<Double>
    let scale: HeatScale

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack {
                Spacer(minLength: 0)
                Sparkline(points: points, range: range, scale: scale)
                    .frame(height: 44)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(value)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 9)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 84)
        .modifier(CardStyle())
        .accessibilityElement(children: .combine)
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
