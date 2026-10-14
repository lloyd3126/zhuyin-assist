import AppKit
import Foundation

// MARK: - 校正歷史資料

// CorrectionHistoryEntry and HistoryOutcome live in TroubleshootingModels.swift.

private final class WindowBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

private final class HistoryTableDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var entries: [CorrectionHistoryEntry] = []
    var onSelection: ((CorrectionHistoryEntry?) -> Void)?
    var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "M/d HH:mm:ss"
        return formatter
    }()

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row), let identifier = tableColumn?.identifier.rawValue else { return nil }
        let entry = entries[row]
        let cell = (tableView.makeView(withIdentifier: tableColumn!.identifier, owner: self) as? NSTableCellView)
            ?? makeCell(identifier: tableColumn!.identifier)
        cell.textField?.stringValue = value(for: identifier, entry: entry)
        cell.textField?.textColor = entry.outcome == .failure ? .systemRed : entry.outcome == .notRestored ? .systemOrange : .labelColor
        cell.textField?.font = NSFont.systemFont(ofSize: 12)
        cell.textField?.lineBreakMode = .byTruncatingTail
        cell.toolTip = entry.detail.isEmpty ? nil : entry.detail
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }
        let row = tableView.selectedRow
        onSelection?(entries.indices.contains(row) ? entries[row] : nil)
    }

    private func value(for identifier: String, entry: CorrectionHistoryEntry) -> String {
        switch identifier {
        case "time": return timeFormatter.string(from: entry.date)
        case "app": return entry.appName
        case "outcome": return entry.outcome.rawValue
        case "elapsed": return String(format: "%.1f 秒", max(0, entry.elapsed))
        default: return ""
        }
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -7),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }
}

final class HistoryWindowController: NSWindowController {
    private let onClear: () -> Void
    /// 主流程若要負責複製，可設定此 callback；視窗本身不碰系統剪貼簿。
    var onCopyResult: ((String) -> Void)?
    private let dataSource = HistoryTableDataSource()
    private let tableView = NSTableView()
    private let originalView = HistoryWindowController.makeTextView()
    private let correctedView = HistoryWindowController.makeTextView()
    private let summaryLabel = NSTextField(labelWithString: "尚未選取校正紀錄")
    private let copyButton = NSButton(title: "複製結果", target: nil, action: nil)
    private let clearButton = NSButton(title: "清除歷史", target: nil, action: nil)

    init(onClear: @escaping () -> Void) {
        self.onClear = onClear
        super.init(window: nil)
        window = makeWindow()
        wireActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(entries: [CorrectionHistoryEntry]) {
        dataSource.entries = Array(entries.sorted { $0.date > $1.date }.prefix(20))
        tableView.reloadData()
        if dataSource.entries.isEmpty {
            show(entry: nil)
        } else {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            show(entry: dataSource.entries[0])
        }
    }

    // Kept internal for the offline window test. It does not expose document text
    // to the production menu or persist anything.
    var testEntryCount: Int { dataSource.entries.count }
    var testCopyEnabled: Bool { copyButton.isEnabled }
    var testOriginalAttributedString: NSAttributedString { originalView.attributedString() }
    var testCorrectedAttributedString: NSAttributedString { correctedView.attributedString() }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "校正歷史"
        window.minSize = NSSize(width: 620, height: 500)
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.contentView = makeContentView()
        return window
    }

    private func makeContentView() -> NSView {
        let root = WindowBackgroundView()
        root.translatesAutoresizingMaskIntoConstraints = true

        let title = NSTextField(labelWithString: "校正歷史")
        title.font = .boldSystemFont(ofSize: 20)
        let privacy = NSTextField(labelWithString: "只保留本次開啟 App 後的最近 20 筆；關閉 App 後會清除。")
        privacy.textColor = .secondaryLabelColor
        privacy.font = .systemFont(ofSize: 12)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = tableView
        tableView.frame = NSRect(x: 0, y: 0, width: 700, height: 210)
        tableView.autoresizingMask = [.width]
        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 25
        tableView.intercellSpacing = NSSize(width: 6, height: 0)
        tableView.selectionHighlightStyle = .regular
        tableView.delegate = dataSource
        tableView.dataSource = dataSource
        addColumn("time", title: "時間", width: 105)
        addColumn("app", title: "程式", width: 150)
        addColumn("outcome", title: "結果", width: 100)
        addColumn("elapsed", title: "耗時", width: 85)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        dataSource.onSelection = { [weak self] entry in self?.show(entry: entry) }

        let detailTitle = NSTextField(labelWithString: "內容")
        detailTitle.font = .boldSystemFont(ofSize: 13)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.font = .systemFont(ofSize: 12)
        summaryLabel.lineBreakMode = .byTruncatingTail

        let originalBox = makeTextBox(title: "原文", textView: originalView)
        let correctedBox = makeTextBox(title: "校正結果", textView: correctedView)
        let textSplit = NSStackView(views: [originalBox, correctedBox])
        textSplit.translatesAutoresizingMaskIntoConstraints = false
        textSplit.orientation = .horizontal
        textSplit.distribution = .fillEqually
        textSplit.spacing = 12

        copyButton.bezelStyle = .rounded
        clearButton.bezelStyle = .rounded
        let bottom = NSStackView(views: [copyButton, clearButton])
        bottom.orientation = .horizontal
        bottom.alignment = .centerY
        bottom.spacing = 8
        bottom.translatesAutoresizingMaskIntoConstraints = false

        let layout = NSStackView(views: [title, privacy, scroll, detailTitle, summaryLabel, textSplit, bottom])
        layout.orientation = .vertical
        layout.alignment = .leading
        layout.spacing = 8
        layout.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(layout)
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            layout.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            layout.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            layout.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            title.widthAnchor.constraint(equalTo: layout.widthAnchor),
            privacy.widthAnchor.constraint(equalTo: layout.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: layout.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
            detailTitle.widthAnchor.constraint(equalTo: layout.widthAnchor),
            summaryLabel.widthAnchor.constraint(equalTo: layout.widthAnchor),
            textSplit.widthAnchor.constraint(equalTo: layout.widthAnchor),
            textSplit.heightAnchor.constraint(greaterThanOrEqualToConstant: 190),
            bottom.widthAnchor.constraint(equalTo: layout.widthAnchor),
            bottom.heightAnchor.constraint(equalToConstant: 28)
        ])
        return root
    }

    private func wireActions() {
        copyButton.target = self
        copyButton.action = #selector(copySelectedResult)
        copyButton.isEnabled = false
        clearButton.target = self
        clearButton.action = #selector(clearHistory)
    }

    private func addColumn(_ id: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.minWidth = width * 0.7
        tableView.addTableColumn(column)
    }

    private func makeTextBox(title: String, textView: NSTextView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 12)
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = textView
        textView.frame = NSRect(x: 0, y: 0, width: 320, height: 160)
        let stack = NSStackView(views: [label, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        return stack
    }

    private static func makeTextView() -> NSTextView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = true
        view.backgroundColor = .textBackgroundColor
        view.font = .systemFont(ofSize: 13)
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 160)
        view.autoresizingMask = [.width, .height]
        return view
    }

    private func show(entry: CorrectionHistoryEntry?) {
        guard let entry else {
            summaryLabel.stringValue = "尚未選取校正紀錄"
            originalView.textStorage?.setAttributedString(NSAttributedString(string: ""))
            correctedView.textStorage?.setAttributedString(NSAttributedString(string: ""))
            copyButton.isEnabled = false
            return
        }
        let resultText = entry.corrected
        let status = entry.detail.isEmpty ? entry.outcome.rawValue : "\(entry.outcome.rawValue) · \(entry.detail)"
        let longTextNote = (entry.original.count > 2_000 || (resultText?.count ?? 0) > 2_000)
            ? " · 長文字僅標示變更範圍"
            : ""
        summaryLabel.stringValue = "\(entry.appName) · \(status) · \(String(format: "%.1f", max(0, entry.elapsed))) 秒\(longTextNote)"
        originalView.textStorage?.setAttributedString(attributedDifference(original: entry.original, corrected: resultText))
        if let resultText {
            correctedView.textStorage?.setAttributedString(attributedDifference(original: entry.original, corrected: resultText, showOnly: .corrected))
            copyButton.isEnabled = true
        } else {
            correctedView.textStorage?.setAttributedString(NSAttributedString(string: "\n（沒有已確認的校正結果，請查看原因並檢查目前文字。）", attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
            copyButton.isEnabled = false
        }
    }

    @objc private func copySelectedResult() {
        guard let entry = dataSource.entries[safe: tableView.selectedRow], let result = entry.corrected else { return }
        onCopyResult?(result)
    }

    @objc private func clearHistory() {
        onClear()
        dataSource.entries.removeAll()
        tableView.reloadData()
        show(entry: nil)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private enum DifferenceSide { case original, corrected }

private func attributedDifference(original: String, corrected: String?, showOnly side: DifferenceSide? = nil) -> NSAttributedString {
    guard let corrected else {
        return NSAttributedString(string: original, attributes: [.foregroundColor: NSColor.labelColor])
    }
    let normal: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.labelColor]
    let changed: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.labelColor,
        .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.32)
    ]
    let value = side == .corrected ? corrected : original
    let attributed = NSMutableAttributedString(string: value, attributes: normal)
    let chars = Array(original)
    let other = Array(corrected)
    let displayed = side == .corrected ? other : chars
    guard chars.count <= 2_000, other.count <= 2_000 else {
        let prefix = commonPrefixLength(chars, other)
        let suffix = commonSuffixLength(chars, other, prefix: prefix)
        let start = min(prefix, displayed.count)
        let end = max(start, displayed.count - suffix)
        if end > start {
            let range = NSRange(
                location: utf16Offset(of: value, characterIndex: start),
                length: utf16Offset(of: value, characterIndex: end) - utf16Offset(of: value, characterIndex: start)
            )
            if range.length > 0 { attributed.addAttributes(changed, range: range) }
        }
        return attributed
    }

    // CollectionDifference keeps the edit window bounded to a normal paragraph.
    // Remove offsets belong to the original collection, while insert offsets
    // belong to the resulting collection. Mark only the change type belonging
    // to the side currently displayed, then convert its offsets to UTF-16.
    let difference = other.difference(from: chars)
    var indexes = Set<Int>()
    for change in difference {
        switch change {
        case .remove(let offset, _, _):
            if side != .corrected { indexes.insert(offset) }
        case .insert(let offset, _, _):
            if side == .corrected { indexes.insert(offset) }
        @unknown default: break
        }
    }
    guard !indexes.isEmpty else { return attributed }
    var ranges: [Range<Int>] = []
    for index in indexes.sorted() {
        // CollectionDifference offsets identify the changed element on their
        // respective side. Mark that grapheme only; do not color its neighbor.
        guard index >= 0, index < displayed.count else { continue }
        let start = index
        let end = index + 1
        if start < end { ranges.append(start..<end) }
    }
    let merged = ranges.sorted { $0.lowerBound < $1.lowerBound }.reduce(into: [Range<Int>]()) { result, next in
        guard let last = result.last else { result.append(next); return }
        if next.lowerBound <= last.upperBound {
            result[result.count - 1] = last.lowerBound..<max(last.upperBound, next.upperBound)
        } else { result.append(next) }
    }
    for range in merged {
        let start = utf16Offset(of: value, characterIndex: range.lowerBound)
        let end = utf16Offset(of: value, characterIndex: range.upperBound)
        if end > start { attributed.addAttributes(changed, range: NSRange(location: start, length: end - start)) }
    }
    return attributed
}

private func commonPrefixLength(_ lhs: [Character], _ rhs: [Character]) -> Int {
    var count = 0
    while count < lhs.count, count < rhs.count, lhs[count] == rhs[count] { count += 1 }
    return count
}

private func commonSuffixLength(_ lhs: [Character], _ rhs: [Character], prefix: Int) -> Int {
    var count = 0
    while count < lhs.count - prefix, count < rhs.count - prefix,
          lhs[lhs.count - count - 1] == rhs[rhs.count - count - 1] { count += 1 }
    return count
}

private func utf16Offset(of value: String, characterIndex: Int) -> Int {
    guard characterIndex > 0 else { return 0 }
    return Array(value.prefix(characterIndex)).reduce(0) { $0 + String($1).utf16.count }
}

// MARK: - 檢查與測試視窗

final class DiagnosticsWindowController: NSWindowController {
    private let onTest: () -> Void
    private let onToggleMode: () -> Void
    private let onCopy: () -> Void
    private let checksStack = NSStackView()
    private let latestLabel = NSTextField(labelWithString: "尚無檢查結果")
    private let apiLabel = NSTextField(labelWithString: "尚未測試 Gemini")
    private let stepLabel = NSTextField(labelWithString: "目前沒有校正工作")
    private let reportView = DiagnosticsWindowController.makeReportTextView()
    private let reportScroll = NSScrollView()
    private let testButton = NSButton(title: "測試 Gemini", target: nil, action: nil)
    private let modeButton = NSButton(title: "開始 30 秒檢查", target: nil, action: nil)
    private let copyButton = NSButton(title: "複製診斷報告", target: nil, action: nil)

    init(onTest: @escaping () -> Void, onToggleMode: @escaping () -> Void, onCopy: @escaping () -> Void) {
        self.onTest = onTest
        self.onToggleMode = onToggleMode
        self.onCopy = onCopy
        super.init(window: nil)
        window = makeWindow()
        wireActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(state: DiagnosticViewState) {
        checksStack.arrangedSubviews.forEach { checksStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        if state.checks.isEmpty {
            checksStack.addArrangedSubview(checkRow(title: "尚未完成基本檢查", passed: false, detail: "開啟此視窗後可執行檢查。"))
        } else {
            state.checks.prefix(4).forEach { checksStack.addArrangedSubview(checkRow(title: $0.title, passed: $0.passed, detail: $0.detail)) }
        }
        latestLabel.stringValue = state.latest.isEmpty ? "尚無檢查結果" : state.latest
        apiLabel.stringValue = "Gemini：\(state.apiStatus.isEmpty ? "尚未測試" : state.apiStatus)"
        stepLabel.stringValue = state.correctionBusy ? "目前正在校正文字……" : "目前沒有校正工作"
        reportView.string = state.report.isEmpty ? "尚無診斷紀錄" : state.report
        testButton.isEnabled = !state.apiBusy && !state.correctionBusy
        modeButton.title = state.modeActive ? "停止檢查" : "開始 30 秒檢查"
        modeButton.isEnabled = !state.correctionBusy
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "檢查與測試"
        window.minSize = NSSize(width: 500, height: 520)
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.contentView = makeContentView()
        return window
    }

    private func makeContentView() -> NSView {
        let root = WindowBackgroundView()
        root.translatesAutoresizingMaskIntoConstraints = true
        let title = NSTextField(labelWithString: "檢查與測試")
        title.font = .boldSystemFont(ofSize: 20)
        let help = NSTextField(labelWithString: "這裡只顯示目前狀態，不會記錄按鍵內容。測試 Gemini 只會送出固定範例。")
        help.textColor = .secondaryLabelColor
        help.font = .systemFont(ofSize: 12)
        help.lineBreakMode = .byWordWrapping
        help.maximumNumberOfLines = 2

        let checksTitle = sectionLabel("基本檢查")
        checksStack.orientation = .vertical
        checksStack.alignment = .leading
        checksStack.spacing = 7
        checksStack.setContentHuggingPriority(.required, for: .vertical)
        checksStack.setContentCompressionResistancePriority(.required, for: .vertical)

        let apiTitle = sectionLabel("Gemini 測試")
        apiLabel.textColor = .secondaryLabelColor
        apiLabel.lineBreakMode = .byTruncatingTail
        let stepTitle = sectionLabel("處理步驟")
        stepLabel.textColor = .secondaryLabelColor
        stepLabel.lineBreakMode = .byTruncatingTail
        latestLabel.textColor = .secondaryLabelColor
        latestLabel.lineBreakMode = .byTruncatingTail

        let reportTitle = sectionLabel("診斷紀錄")
        reportScroll.translatesAutoresizingMaskIntoConstraints = false
        reportScroll.hasVerticalScroller = true
        reportScroll.borderType = .bezelBorder
        reportScroll.documentView = reportView
        reportView.frame = NSRect(x: 0, y: 0, width: 500, height: 145)
        reportView.autoresizingMask = [.width]

        let buttons = NSStackView(views: [testButton, modeButton, copyButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY
        buttons.translatesAutoresizingMaskIntoConstraints = false
        [testButton, modeButton, copyButton].forEach { $0.bezelStyle = .rounded }

        let stack = NSStackView(views: [title, help, checksTitle, checksStack, apiTitle, apiLabel, stepTitle, stepLabel, latestLabel, reportTitle, reportScroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            title.widthAnchor.constraint(equalTo: stack.widthAnchor),
            help.widthAnchor.constraint(equalTo: stack.widthAnchor),
            checksTitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            checksStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            checksStack.heightAnchor.constraint(equalToConstant: 117),
            apiTitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            apiLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            stepTitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            stepLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            latestLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            reportTitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            reportScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            reportScroll.heightAnchor.constraint(equalToConstant: 160),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.heightAnchor.constraint(equalToConstant: 30)
        ])
        return root
    }

    private func wireActions() {
        testButton.target = self
        testButton.action = #selector(testGemini)
        modeButton.target = self
        modeButton.action = #selector(toggleMode)
        copyButton.target = self
        copyButton.action = #selector(copyReport)
    }

    private func sectionLabel(_ value: String) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.font = .boldSystemFont(ofSize: 13)
        return label
    }

    private static func makeReportTextView() -> NSTextView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        view.textContainerInset = NSSize(width: 8, height: 8)
        return view
    }

    private func checkRow(title: String, passed: Bool, detail: String) -> NSView {
        let icon = NSTextField(labelWithString: passed ? "✓" : "!" )
        icon.font = .boldSystemFont(ofSize: 14)
        icon.textColor = passed ? .systemGreen : .systemOrange
        icon.alignment = .center
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.lineBreakMode = .byTruncatingTail
        let row = NSStackView(views: [icon, titleLabel, detailLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 5
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 500).isActive = true
        row.heightAnchor.constraint(equalToConstant: 24).isActive = true
        row.setContentHuggingPriority(.required, for: .vertical)
        row.setContentCompressionResistancePriority(.required, for: .vertical)
        return row
    }

    @objc private func testGemini() { onTest() }
    @objc private func toggleMode() { onToggleMode() }
    @objc private func copyReport() { onCopy() }
}

// MARK: - 不搶焦點的檢查提示

final class DiagnosticOverlay {
    private let panel: NSPanel
    private let label: NSTextField

    init() {
        label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 42),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = background
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: background.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -8)
        ])
    }

    func show(message: String) {
        label.stringValue = "檢查模式：\(message)"
        let size = label.intrinsicContentSize
        let width = min(max(240, size.width + 24), 420)
        let height = max(42, size.height + 16)
        panel.setContentSize(NSSize(width: width, height: height))
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.maxX - width - 18, y: frame.maxY - height - 18))
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

// MARK: - 離屏視窗測試

/// 建立並檢查歷史／診斷視窗，不顯示視窗、不送網路、不讀金鑰、不碰真實剪貼簿。
/// 渲染結果會寫到固定的暫存預覽路徑，方便主流程以 `--windows-test` 驗證畫面。
func troubleshootingWindowTest() throws {
    func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw fail(message) }
    }

    let history = HistoryWindowController(onClear: {})
    history.update(entries: [])
    try check(history.testEntryCount == 0, "Empty history should have no rows")
    try check(!history.testCopyEnabled, "Copy must be disabled when history is empty")

    let now = Date(timeIntervalSince1970: 1_000)
    let twenty = (0..<20).map { index in
        CorrectionHistoryEntry(
            id: UUID(), date: now.addingTimeInterval(TimeInterval(index)), appName: "測試程式",
            original: "原文 (index)", corrected: "校正結果 (index)", outcome: .modified,
            elapsed: 0.4, detail: "已完成"
        )
    }
    history.update(entries: twenty)
    try check(history.testEntryCount == 20, "History should render the newest 20 entries")
    try check(history.testCopyEnabled, "Copy should be enabled for a corrected result")

    let cancelled = CorrectionHistoryEntry(
        id: UUID(), date: now.addingTimeInterval(200), appName: "測試程式",
        original: "使用者取消的文字", corrected: nil, outcome: .cancelled,
        elapsed: 0.1, detail: "已取消"
    )
    let failure = CorrectionHistoryEntry(
        id: UUID(), date: now.addingTimeInterval(201), appName: "測試程式",
        original: "失敗的文字", corrected: nil, outcome: .failure,
        elapsed: 0.2, detail: "測試失敗"
    )
    history.update(entries: [cancelled])
    try check(!history.testCopyEnabled, "Cancelled result must not offer a copy result")
    try check(history.testCorrectedAttributedString.string.contains("沒有已確認的校正結果"), "Cancelled result should use a neutral explanation")
    try check(!history.testCorrectedAttributedString.string.contains("原文已保留"), "Cancelled result must not claim the original was preserved")
    history.update(entries: [failure])
    try check(!history.testCopyEnabled, "Failed result must not offer a copy result")
    try check(history.testCorrectedAttributedString.string.contains("沒有已確認的校正結果"), "Failed result should use a neutral explanation")
    try check(!history.testCorrectedAttributedString.string.contains("原文已保留"), "Failed result must not claim the original was preserved")

    let diffCases: [(String, String)] = [
        ("今天😀很好", "今天😄很好"),
        ("輸入法選自", "輸入法選字"),
        ("前後文字", "前文字"),
        ("前文字", "前後文字"),
        (String(repeating: "長文字😀", count: 430), String(repeating: "長文字😄", count: 428)),
        (String(repeating: "短文字", count: 430), String(repeating: "短文字加上內容", count: 440))
    ]
    for (original, corrected) in diffCases {
        let left = attributedDifference(original: original, corrected: corrected)
        let right = attributedDifference(original: original, corrected: corrected, showOnly: .corrected)
        try check(left.length == (original as NSString).length, "Original difference range must stay valid")
        try check(right.length == (corrected as NSString).length, "Corrected difference range must stay valid")
        try check(validAttributeRanges(left) && validAttributeRanges(right), "Difference attributes must stay inside text bounds")
    }

    let emojiOriginal = attributedDifference(original: "今天😀很好", corrected: "今天😄很好")
    let emojiCorrected = attributedDifference(original: "今天😀很好", corrected: "今天😄很好", showOnly: .corrected)
    try check(highlightedRanges(emojiOriginal) == [NSRange(location: 2, length: 2)], "Emoji original range should be exactly UTF-16 location 2 length 2")
    try check(highlightedRanges(emojiCorrected) == [NSRange(location: 2, length: 2)], "Emoji corrected range should be exactly UTF-16 location 2 length 2")

    let combiningOriginal = attributedDifference(original: "e\u{301}clair", corrected: "èclair")
    let combiningCorrected = attributedDifference(original: "e\u{301}clair", corrected: "èclair", showOnly: .corrected)
    try check(highlightedRanges(combiningOriginal) == [NSRange(location: 0, length: 2)], "Combining original range should include the complete grapheme")
    try check(highlightedRanges(combiningCorrected) == [NSRange(location: 0, length: 1)], "Composed corrected range should include the complete grapheme")

    let removedSpace = attributedDifference(original: "a b", corrected: "ab")
    let insertedSpace = attributedDifference(original: "ab", corrected: "a b", showOnly: .corrected)
    try check(highlightedRanges(removedSpace) == [NSRange(location: 1, length: 1)], "Removed space should highlight only the original space")
    try check(highlightedRanges(insertedSpace) == [NSRange(location: 1, length: 1)], "Inserted space should highlight only the corrected space")

    let diagnostics = DiagnosticsWindowController(onTest: {}, onToggleMode: {}, onCopy: {})
    diagnostics.update(state: DiagnosticViewState(
        checks: [
            DiagnosticCheck(title: "Gemini 金鑰", passed: true, detail: "已設定"),
            DiagnosticCheck(title: "輔助使用", passed: true, detail: "已允許"),
            DiagnosticCheck(title: "輸入監控", passed: false, detail: "尚未允許"),
            DiagnosticCheck(title: "快捷鍵", passed: true, detail: "已啟用")
        ],
        latest: "已完成固定範例檢查",
        apiStatus: "連線成功，校正測試通過 · 0.8 秒",
        apiBusy: false,
        correctionBusy: false,
        modeActive: false,
        report: "固定範例診斷報告"
    ))

    // Leave the preview on a normal successful correction so the generated
    // image is useful for visually checking the two text panes.
    history.update(entries: [CorrectionHistoryEntry(
        id: UUID(), date: now.addingTimeInterval(300), appName: "TextEdit",
        original: "這個輸入法的選自不太準。", corrected: "這個輸入法的選字不太準。",
        outcome: .modified, elapsed: 0.8, detail: "已完成"
    )])

    try renderOffscreen(history.window, to: "/private/tmp/zhuyin-assist-history-preview.png")
    try renderOffscreen(diagnostics.window, to: "/private/tmp/zhuyin-assist-diagnostics-preview.png")
    print("PASS: history/diagnostics offscreen windows, copy-state guards, and bounded difference ranges")
}

private func validAttributeRanges(_ value: NSAttributedString) -> Bool {
    guard value.length > 0 else { return true }
    var valid = true
    value.enumerateAttributes(in: NSRange(location: 0, length: value.length), options: []) { _, range, stop in
        if range.location < 0 || range.length < 0 || NSMaxRange(range) > value.length {
            valid = false
            stop.pointee = true
        }
    }
    return valid
}

private func highlightedRanges(_ value: NSAttributedString) -> [NSRange] {
    var ranges: [NSRange] = []
    value.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: value.length), options: []) { attribute, range, _ in
        if attribute != nil { ranges.append(range) }
    }
    return ranges
}

private func renderOffscreen(_ window: NSWindow?, to path: String) throws {
    guard let window, let view = window.contentView else { throw fail("無法建立視窗預覽。") }
    // A content view assigned to an unseen window does not always receive its
    // final frame through AppKit's window layout pass. Give it the exact size
    // that the real window would use before resolving the constraints.
    let size = window.frame.size
    view.translatesAutoresizingMaskIntoConstraints = true
    view.frame = NSRect(origin: .zero, size: size)
    view.autoresizingMask = [.width, .height]
    layoutAndDisplay(view)
    let bounds = view.bounds
    // PDF drawing includes layer-backed table cells that cacheDisplay can omit
    // for a window that has never appeared on screen.
    try view.dataWithPDF(inside: bounds).write(to: URL(fileURLWithPath: path + ".pdf"), options: .atomic)
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else { throw fail("無法建立視窗預覽影像。") }
    view.cacheDisplay(in: bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw fail("無法儲存視窗預覽影像。") }
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

private func layoutAndDisplay(_ view: NSView) {
    view.layoutSubtreeIfNeeded()
    view.subviews.forEach(layoutAndDisplay)
    view.needsDisplay = true
    view.displayIfNeeded()
}
