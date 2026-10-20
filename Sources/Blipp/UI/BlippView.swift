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

import AppKit
import QuartzCore
import SwiftUI

/// Animated, full-detail Blipp for the panel.
///
/// Drawn into its own Core Animation layer: each frame only asks that layer to redraw, so the
/// panel's SwiftUI views and AppKit layout aren't touched 24 times a second.
struct BlippView: NSViewRepresentable {
    let scene: BlippScene
    /// Size of Blipp's 64-unit body box. The view adds headroom for things above his head.
    var size: CGFloat
    var animated = true
    /// Pick a random opening animation each time (otherwise always the first that fits).
    var variedIntro = true

    func makeNSView(context: Context) -> BlippCanvasView {
        let view = BlippCanvasView(scene: scene, blippSize: size)
        view.animated = animated
        view.variedIntro = variedIntro
        return view
    }

    func updateNSView(_ view: BlippCanvasView, context: Context) {
        view.scene = scene
        view.blippSize = size
        view.animated = animated
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BlippCanvasView, context: Context) -> CGSize? {
        CGSize(width: size * 1.25, height: size * 1.3)
    }
}

final class BlippCanvasView: NSView {
    static let framesPerSecond = 24.0

    var scene: BlippScene {
        get { blippLayer.scene }
        set { if newValue != blippLayer.scene { blippLayer.scene = newValue; blippLayer.setNeedsDisplay() } }
    }
    var blippSize: CGFloat {
        get { blippLayer.blippSize }
        set { if newValue != blippLayer.blippSize { blippLayer.blippSize = newValue; blippLayer.setNeedsDisplay() } }
    }
    var animated = true {
        didSet { if animated != oldValue { updateTimer() } }
    }
    var variedIntro = true

    private let blippLayer = BlippLayer()
    private var timer: Timer?

    init(scene: BlippScene, blippSize: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        blippLayer.scene = scene
        blippLayer.blippSize = blippSize
        layer?.addSublayer(blippLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Blipp")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        blippLayer.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        blippLayer.contentsScale = window?.backingScaleFactor ?? 2
        blippLayer.setNeedsDisplay()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        blippLayer.contentsScale = window?.backingScaleFactor ?? 2
        // Every time the panel opens, Blipp greets you with a little animation that fits his state.
        if window != nil, shouldAnimate {
            blippLayer.intro = BlippIntro.random(for: blippLayer.scene, varied: variedIntro)
            blippLayer.introStart = ProcessInfo.processInfo.systemUptime
        }
        updateTimer()
    }

    private var shouldAnimate: Bool {
        animated && window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func updateTimer() {
        blippLayer.animated = shouldAnimate
        blippLayer.setNeedsDisplay()
        guard shouldAnimate else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1 / Self.framesPerSecond, repeats: true) { [weak self] _ in
            self?.blippLayer.setNeedsDisplay()
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }
}

private final class BlippLayer: CALayer {
    var scene = BlippScene()
    var blippSize: CGFloat = 50
    var animated = true
    var intro: BlippIntro.Kind?
    var introStart: TimeInterval = 0

    override init() {
        super.init()
        needsDisplayOnBoundsChange = true
        actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
    }

    override init(layer: Any) {
        super.init(layer: layer)
        if let other = layer as? BlippLayer {
            scene = other.scene
            blippSize = other.blippSize
            animated = other.animated
            intro = other.intro
            introStart = other.introStart
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(in ctx: CGContext) {
        // Layers draw with a bottom-left origin; Blipp is designed top-down.
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        let now = ProcessInfo.processInfo.systemUptime
        let time = animated ? now : 0.4
        let origin = CGPoint(x: (bounds.width - blippSize) / 2, y: bounds.height - blippSize * 1.02)
        var playing: BlippIntro?
        if animated, let intro {
            let progress = (now - introStart) / BlippIntro.duration
            if progress < 1 { playing = BlippIntro(kind: intro, progress: max(0, progress)) } else { self.intro = nil }
        }
        BlippRenderer.draw(scene, in: ctx, origin: origin, size: blippSize, time: time, intro: playing)
    }
}
