import AppKit
import ScreenCaptureKit

func emit(_ value: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: value)
    print(String(data: data, encoding: .utf8)!)
    fflush(stdout)
}

final class Controller: NSObject, NSApplicationDelegate {
    var cover: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        emit(["ready": true, "permission": CGPreflightScreenCaptureAccess()])
        Thread.detachNewThread {
            while let line = readLine() {
                guard let data = line.data(using: .utf8),
                      let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                DispatchQueue.main.async { self.handle(request) }
            }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    func handle(_ request: [String: Any]) {
        let token = request["token"] as! Int
        switch request["command"] as! String {
        case "cover":
            let rows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
            guard let target = rows.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == request["pid"] as? Int32 && $0[kCGWindowName as String] as? String == "Proton Occlusion Regression" }),
                  let bounds = target[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else {
                emit(["token": token, "error": "Target window is missing"])
                return
            }
            // AppKit uses bottom-left coordinates; CGWindowList uses top-left.
            // Position on the target's display, not whichever display is main.
            let frame = CGRect(x: rect.minX - 40, y: NSScreen.screens[0].frame.maxY - rect.maxY - 40,
                               width: rect.width + 80, height: rect.height + 80)
            let window = NSWindow(contentRect: frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.title = "Proton Occlusion Cover"
            window.backgroundColor = .orange
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.level = .screenSaver
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            cover = window
            emit(["token": token])
        case "fullscreen":
            cover!.level = .normal
            cover!.collectionBehavior = [.fullScreenPrimary]
            cover!.toggleFullScreen(nil)
            emit(["token": token])
        case "uncover":
            cover?.orderOut(nil)
            NSRunningApplication(processIdentifier: request["pid"] as! Int32)?.activate(options: [.activateAllWindows])
            emit(["token": token])
        case "state", "capture":
            Task { @MainActor in
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                    guard let window = content.windows.first(where: { $0.owningApplication?.processID == request["pid"] as? Int32 && $0.title == "Proton Occlusion Regression" }) else {
                        throw NSError(domain: "occlusion", code: 1, userInfo: [NSLocalizedDescriptionKey: "Target window is missing"])
                    }
                    if request["command"] as? String == "state" {
                        emit(["token": token, "onscreen": window.isOnScreen])
                        return
                    }
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    let config = SCStreamConfiguration()
                    config.width = Int(window.frame.width)
                    config.height = Int(window.frame.height)
                    config.showsCursor = false
                    config.ignoreShadowsSingleWindow = true
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    let color = bitmap.colorAt(x: image.width / 2, y: image.height / 2)!.usingColorSpace(.sRGB)!
                    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: request["path"] as! String))
                    // CGWindowList is front-to-back; prove the opaque cover contains the target.
                    let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
                    let targetIndex = rows.firstIndex { ($0[kCGWindowNumber as String] as? UInt32) == window.windowID }
                    let coverIndex = rows.firstIndex { ($0[kCGWindowNumber as String] as? Int) == self.cover?.windowNumber }
                    var covered = false
                    if let targetIndex, let coverIndex, coverIndex < targetIndex,
                       let bounds = rows[coverIndex][kCGWindowBounds as String] as? NSDictionary,
                       let rect = CGRect(dictionaryRepresentation: bounds) {
                        covered = rect.contains(window.frame)
                    }
                    emit(["token": token, "onscreen": window.isOnScreen, "covered": covered,
                          "rgb": [color.redComponent, color.greenComponent, color.blueComponent],
                          "frame": NSStringFromRect(window.frame),
                          "frontmostPid": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0])
                } catch { emit(["token": token, "error": String(describing: error)]) }
            }
        case "quit":
            cover?.close()
            emit(["token": token])
            NSApp.terminate(nil)
        default:
            emit(["token": token, "error": "Unknown command"])
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let controller = Controller()
app.delegate = controller
app.run()
