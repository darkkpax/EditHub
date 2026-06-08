import AppKit
import SwiftUI

struct DesktopWallpaperView: NSViewRepresentable {
    var cornerRadius: CGFloat = 10

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        view.isEmphasized = true
        view.alphaValue = 1
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor
    }
}
