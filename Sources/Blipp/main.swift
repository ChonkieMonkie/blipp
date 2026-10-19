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

if arguments.contains("--benchmark") {
    Benchmark.run()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
