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

let arguments = CommandLine.arguments

if arguments.count >= 3, arguments[1] == "--export-iconset" {
    do {
        try IconExporter.exportIconset(to: arguments[2])
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Icon export failed: \(error)\n".utf8))
        exit(1)
    }
}

if arguments.count >= 3, arguments[1] == "--render-gallery" {
    MainActor.assumeIsolated { PreviewRenderer.renderGallery(to: arguments[2]) }
    exit(0)
}

if arguments.count >= 3, arguments[1] == "--render-readme" {
    MainActor.assumeIsolated { ReadmeImages.render(to: arguments[2]) }
    exit(0)
}

if arguments.count >= 3, arguments[1] == "--render-animations" {
    MainActor.assumeIsolated { ReadmeAnimations.render(to: arguments[2]) }
    exit(0)
}

if arguments.contains("--benchmark") {
    Benchmark.run()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
