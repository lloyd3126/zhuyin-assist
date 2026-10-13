import AppKit
import ApplicationServices

// This panel never becomes a responder or changes the document's text/selection.
private final class ProcessingHintPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ProcessingHint {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "校正中")
    private let spinner = NSProgressIndicator()
    private let snapshot: Snapshot
    private var timer: Timer?
    var isVisible: Bool { panel.isVisible }

    init(snapshot: Snapshot) {
        self.snapshot = snapshot
        panel = ProcessingHintPanel(contentRect: NSRect(x: 0, y: 0, width: 92, height: 28),
                                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .none
        let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 92, height: 28))
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        spinner.frame = NSRect(x: 9, y: 6, width: 16, height: 16)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.usesThreadedAnimation = true
        spinner.isDisplayedWhenStopped = false
        background.addSubview(spinner)
        label.frame = NSRect(x: 32, y: 5, width: 52, height: 19)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        background.addSubview(label)
        panel.contentView = background
    }

    func show() {
        precondition(Thread.isMainThread)
        hide()
        update()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.update()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func hide() {
        timer?.invalidate(); timer = nil
        spinner.stopAnimation(nil)
        panel.orderOut(nil)
    }

    private func update() {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.pid,
              let frame = placement() else {
            spinner.stopAnimation(nil)
            panel.orderOut(nil)
            return
        }
        panel.setFrame(frame, display: true)
        if !panel.isVisible {
            panel.orderFrontRegardless()
            spinner.startAnimation(nil)
        }
    }

    private func bounds(for range: NSRange) -> CGRect? {
        var range = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(snapshot.element,
                  kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &result) == .success,
              let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(result as! AXValue, .cgRect, &rect), valid(rect) else { return nil }
        return rect
    }

    private func fieldBounds() -> CGRect? {
        guard let position = attribute(snapshot.element, kAXPositionAttribute),
              let size = attribute(snapshot.element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        let rect = CGRect(origin: point, size: dimensions)
        return valid(rect) ? rect : nil
    }

    private func valid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite
            && rect.width >= 0 && rect.height > 0
    }

    private func placement() -> NSRect? {
        // AX coordinates start at the primary display's top left. AppKit uses
        // its bottom left, including displays placed above/below the primary one.
        guard let primary = NSScreen.screens.first else { return nil }
        func appKitRect(_ rect: CGRect) -> NSRect {
            NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        let end = NSMaxRange(snapshot.paragraph)
        let lastCharacter = (snapshot.text as NSString).rangeOfComposedCharacterSequence(at: end - 1)
        let textBounds = bounds(for: NSRange(location: end, length: 0)) ?? bounds(for: lastCharacter)
        let field = fieldBounds().map(appKitRect)
        var anchor: NSRect?
        var screen: NSScreen?
        if let textBounds {
            let rect = appKitRect(textBounds)
            // A caret may have zero width. Give it a small area for intersection.
            let visible = rect.insetBy(dx: -1, dy: 0)
            screen = NSScreen.screens.first { $0.visibleFrame.intersects(visible) }
            if screen != nil, field == nil || field!.intersects(visible) { anchor = rect }
        }
        if anchor == nil, let field {
            screen = NSScreen.screens.max { lhs, rhs in
                let a = lhs.visibleFrame.intersection(field), b = rhs.visibleFrame.intersection(field)
                return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
            }
            if let screen {
                let visible = screen.visibleFrame.intersection(field)
                if !visible.isNull && visible.width > 0 && visible.height > 0 {
                    anchor = NSRect(x: visible.maxX - 98, y: visible.maxY - 34, width: 0, height: 28)
                }
            }
        }
        guard let anchor, let screen else { return nil }
        let area = screen.visibleFrame.insetBy(dx: 6, dy: 6)
        let size = panel.frame.size
        var x = anchor.maxX + 6
        var y = anchor.midY - size.height / 2
        if x + size.width > area.maxX {
            x = anchor.maxX - size.width
            y = anchor.minY - size.height - 4
            if y < area.minY { y = anchor.maxY + 4 }
        }
        x = min(max(x, area.minX), area.maxX - size.width)
        y = min(max(y, area.minY), area.maxY - size.height)
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    deinit { timer?.invalidate(); spinner.stopAnimation(nil); panel.orderOut(nil) }
}
