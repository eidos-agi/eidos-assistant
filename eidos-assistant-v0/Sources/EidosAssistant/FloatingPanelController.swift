import AppKit
import SwiftUI

/// Floating recording pill — positioned near menu bar for minimal eye travel.
@MainActor
class FloatingPanelController {
    private var panel: NSPanel?

    func show(recorder: AudioRecorderService) {
        guard panel == nil else { return }

        let view = FloatingRecorderView()
            .environmentObject(recorder)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: 44)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 44),
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isFloatingPanel = true
        panel.level = .statusBar  // Just below menu bar level
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        // Position: just below the menu bar, right-of-center
        // This keeps it near where the user's eyes already are (menu bar icon)
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let visibleFrame = screen.visibleFrame
            let menuBarHeight = screenFrame.height - visibleFrame.height - visibleFrame.origin.y
            let x = screenFrame.midX - 50  // Slightly right of center (near status items)
            let y = screenFrame.maxY - menuBarHeight - 52  // Just below menu bar
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}
