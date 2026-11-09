import AppKit
import SwiftUI

extension NSWindow {
    var isOverhearEditor: Bool {
        identifier?.rawValue == "overhear-editor" || identifier?.rawValue.hasPrefix("editor-") == true
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosed), name: NSWindow.willCloseNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosed), name: NSWindow.didMiniaturizeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowShown), name: NSWindow.didBecomeKeyNotification, object: nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @objc private func windowClosed(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.isOverhearEditor else { return }
        NSApp.setActivationPolicy(.accessory)
    }
    @objc private func windowShown(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.isOverhearEditor else { return }
        NSApp.setActivationPolicy(.regular)
    }
}

struct EditorWindowBridge: NSViewRepresentable {
    final class WindowView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.identifier = NSUserInterfaceItemIdentifier("overhear-editor")
            window?.backgroundColor = .black
        }
    }
    func makeNSView(context: Context) -> WindowView { WindowView() }
    func updateNSView(_ nsView: WindowView, context: Context) {}
}

@main
struct OverhearApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Overhear", id: "editor") {
            EditorView(model: model)
                .background(EditorWindowBridge().allowsHitTesting(false))
                .onAppear { NSApp.setActivationPolicy(.regular) }
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.automatic)
        .windowStyle(.titleBar)
        .commands { CommandGroup(replacing: .newItem) {} }

        MenuBarExtra {
            PlacePopoverView(model: model)
        } label: {
            Image(systemName: model.isOn ? "waveform.path" : "waveform.path.badge.minus")
                .accessibilityLabel("Overhear: \(model.statusText)")
        }
        .menuBarExtraStyle(.window)
    }
}
