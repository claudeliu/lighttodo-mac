import AppKit
import UniformTypeIdentifiers

// MARK: - Models

struct Todo: Codable, Equatable {
    var id: UUID
    var text: String
    var completedAt: Date?
    var reminderAt: Date?
    var link: String?

    init(id: UUID = UUID(), text: String = "", completedAt: Date? = nil, reminderAt: Date? = nil, link: String? = nil) {
        self.id = id
        self.text = text
        self.completedAt = completedAt
        self.reminderAt = reminderAt
        self.link = link
    }

    enum CodingKeys: String, CodingKey {
        case id, text, completedAt, reminderAt, link
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        self.reminderAt = try container.decodeIfPresent(Date.self, forKey: .reminderAt)
        self.link = try container.decodeIfPresent(String.self, forKey: .link)
    }
}

struct Appearance: Codable, Equatable {
    var color: String
    var opacity: Double
    var pinned: Bool
    var image: String

    init(color: String = "FFF9D3", opacity: Double = 1.0, pinned: Bool = false, image: String = "") {
        self.color = color
        self.opacity = opacity
        self.pinned = pinned
        self.image = image
    }

    enum CodingKeys: String, CodingKey {
        case color, opacity, pinned, image
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.color = try container.decodeIfPresent(String.self, forKey: .color) ?? "FFF9D3"
        self.opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        self.pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        self.image = try container.decodeIfPresent(String.self, forKey: .image) ?? ""
    }
}

struct Document: Codable {
    var active: [Todo]
    var history: [Todo]
    var appearance: Appearance

    init(active: [Todo] = [Todo()], history: [Todo] = [], appearance: Appearance = Appearance()) {
        self.active = active.isEmpty ? [Todo()] : active
        self.history = history
        self.appearance = appearance
    }

    enum CodingKeys: String, CodingKey {
        case active, history, appearance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var act = try container.decodeIfPresent([Todo].self, forKey: .active) ?? []
        if act.isEmpty { act = [Todo()] }
        self.active = act
        self.history = try container.decodeIfPresent([Todo].self, forKey: .history) ?? []
        self.appearance = try container.decodeIfPresent(Appearance.self, forKey: .appearance) ?? Appearance()
    }
}

enum TodoError: LocalizedError {
    case invalidData, invalidImage
    var errorDescription: String? {
        switch self {
        case .invalidData: return "待办数据格式无效。原文件不会被静默覆盖，请先备份数据目录。"
        case .invalidImage: return "图片无法读取、尺寸过大或格式不受支持。"
        }
    }
}

// MARK: - Store

final class Store {
    let directory: URL
    let file: URL
    let backupFile: URL
    var document: Document

    init(directory: URL) throws {
        self.directory = directory
        self.file = directory.appendingPathComponent("tasks.json")
        self.backupFile = directory.appendingPathComponent("tasks.backup.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: file.path) {
            do {
                document = try Self.read(file)
            } catch let primaryError {
                let damaged = directory.appendingPathComponent("tasks.damaged-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: file, to: damaged)
                guard FileManager.default.fileExists(atPath: backupFile.path) else { throw primaryError }
                document = try Self.read(backupFile)
                try Data(contentsOf: backupFile).write(to: file, options: .atomic)
            }
        } else if FileManager.default.fileExists(atPath: backupFile.path) {
            document = try Self.read(backupFile)
            try Data(contentsOf: backupFile).write(to: file, options: .atomic)
        } else {
            document = Document()
        }

        if document.active.isEmpty { document.active = [Todo()] }
    }

    static func read(_ url: URL) throws -> Document {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 128 * 1024 * 1024 else {
            throw TodoError.invalidData
        }
        let data = try Data(contentsOf: url)
        let value = try JSONDecoder().decode(Document.self, from: data)
        let items = value.active + value.history
        let ids = items.map { $0.id }
        guard ids.count == Set(ids).count,
              value.active.count <= 5000,
              value.history.count <= 50000,
              items.allSatisfy({ $0.text.count <= 10000 && ($0.link?.count ?? 0) <= 4096 }),
              value.appearance.color.range(of: "^[0-9A-Fa-f]{6}$", options: .regularExpression) != nil,
              value.appearance.opacity.isFinite,
              (0.65...1.0).contains(value.appearance.opacity),
              value.appearance.image.count <= 255,
              (value.appearance.image.isEmpty || (value.appearance.image.hasPrefix("background-") && value.appearance.image == (value.appearance.image as NSString).lastPathComponent))
        else { throw TodoError.invalidData }
        return value
    }

    func save() throws {
        let bytes = try JSONEncoder().encode(document)
        if FileManager.default.fileExists(atPath: file.path) {
            try Data(contentsOf: file).write(to: backupFile, options: .atomic)
        }
        try bytes.write(to: file, options: .atomic)
    }

    func replace(with importedDocument: Document) throws {
        let previous = document
        var imported = importedDocument
        if imported.active.isEmpty { imported.active = [Todo()] }
        if !imported.appearance.image.isEmpty,
           !FileManager.default.fileExists(atPath: directory.appendingPathComponent(imported.appearance.image).path) {
            imported.appearance.image = ""
        }
        do {
            let encoder = JSONEncoder()
            let previousBytes = try encoder.encode(previous)
            let importedBytes = try encoder.encode(imported)
            try previousBytes.write(to: backupFile, options: .atomic)
            try importedBytes.write(to: file, options: .atomic)
            document = imported
        } catch {
            document = previous
            throw error
        }
    }

    @discardableResult func add(after id: UUID?) -> UUID {
        let item = Todo()
        let index = id.flatMap { id in document.active.firstIndex { $0.id == id } }.map { $0 + 1 } ?? document.active.count
        document.active.insert(item, at: index)
        return item.id
    }

    func complete(_ id: UUID) {
        guard let index = document.active.firstIndex(where: { $0.id == id }) else { return }
        var item = document.active.remove(at: index)
        item.reminderAt = nil
        item.completedAt = Date()
        document.history.append(item)
        if document.active.isEmpty { document.active = [Todo()] }
    }

    func restore(_ id: UUID) {
        guard let index = document.history.firstIndex(where: { $0.id == id }) else { return }
        var item = document.history.remove(at: index)
        item.completedAt = nil
        item.reminderAt = nil
        document.active.append(item)
    }

    func deleteItem(_ id: UUID) {
        guard let index = document.active.firstIndex(where: { $0.id == id }) else { return }
        document.active.remove(at: index)
        if document.active.isEmpty { document.active = [Todo()] }
    }

    func deleteHistory(_ id: UUID) {
        guard let index = document.history.firstIndex(where: { $0.id == id }) else { return }
        document.history.remove(at: index)
    }

    func clearHistory() {
        document.history.removeAll()
    }

    func takeDueReminders(at date: Date) -> [Todo] {
        var due = [Todo]()
        for index in document.active.indices where document.active[index].reminderAt.map({ $0 <= date }) == true {
            due.append(document.active[index])
            document.active[index].reminderAt = nil
        }
        return due
    }

    func importImage(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 20 * 1024 * 1024 else { throw TodoError.invalidImage }
        guard let original = NSImage(contentsOf: url), let cg = original.cgImage(forProposedRect: nil, context: nil, hints: nil), cg.width * cg.height <= 40_000_000 else { throw TodoError.invalidImage }
        let factor = min(1.0, 1280.0 / Double(max(cg.width, cg.height)))
        let width = max(1, Int(Double(cg.width) * factor)), height = max(1, Int(Double(cg.height) * factor))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: rep) else { throw TodoError.invalidImage }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        original.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let bytes = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else { throw TodoError.invalidImage }
        let name = "background-\(UUID().uuidString).jpg"
        let target = directory.appendingPathComponent(name)
        try bytes.write(to: target, options: .atomic)
        let previous = document.appearance.image
        document.appearance.image = name
        do { try save() } catch { document.appearance.image = previous; try? FileManager.default.removeItem(at: target); throw error }
        removeOwnedImage(previous)
    }

    func removeOwnedImage(_ name: String) {
        guard name.hasPrefix("background-"), name == (name as NSString).lastPathComponent else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
}

// MARK: - Utilities and Components

extension NSColor {
    static func hex(_ value: String) -> NSColor {
        let number = UInt32(value, radix: 16) ?? 0xFFF9D3
        return NSColor(srgbRed: CGFloat((number >> 16) & 255)/255, green: CGFloat((number >> 8) & 255)/255, blue: CGFloat(number & 255)/255, alpha: 1)
    }
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? .white
        return String(format: "%02X%02X%02X", Int(c.redComponent*255), Int(c.greenComponent*255), Int(c.blueComponent*255))
    }
}

final class ActionButton: NSButton {
    var actionBlock: ((ActionButton) -> Void)?
    convenience init(title: String, symbol: String? = nil, tip: String? = nil, accessibility: String? = nil, action: @escaping () -> Void) {
        self.init(frame: .zero)
        self.title = title
        actionBlock = { _ in action() }
        target = self
        self.action = #selector(invoke)
        bezelStyle = .texturedRounded
        toolTip = tip
        setAccessibilityLabel(accessibility ?? tip ?? title)
        if let symbol = symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibility ?? tip)
            imagePosition = .imageOnly
            isBordered = false
        }
    }
    convenience init(title: String, symbol: String? = nil, tip: String? = nil, accessibility: String? = nil, senderAction: @escaping (ActionButton) -> Void) {
        self.init(frame: .zero)
        self.title = title
        actionBlock = senderAction
        target = self
        self.action = #selector(invoke)
        bezelStyle = .texturedRounded
        toolTip = tip
        setAccessibilityLabel(accessibility ?? tip ?? title)
        if let symbol = symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibility ?? tip)
            imagePosition = .imageOnly
            isBordered = false
        }
    }
    @objc func invoke() { actionBlock?(self) }
}

final class ClosureMenuItem: NSMenuItem {
    var actionBlock: (() -> Void)?
    convenience init(_ title: String, key: String = "", action: @escaping () -> Void) {
        self.init(title: title, action: #selector(invoke), keyEquivalent: key)
        actionBlock = action
        target = self
    }
    @objc func invoke() { actionBlock?() }
}

final class ItemField: NSTextField {
    var itemID = UUID()
}

final class Surface: NSView {
    var paper = NSColor.hex("FFF9D3") { didSet { needsDisplay = true } }
    var picture: NSImage? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        paper.setFill()
        bounds.fill()
        guard let image = picture, image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(bounds.width/image.size.width, bounds.height/image.size.height)
        let size = NSSize(width: image.size.width*scale, height: image.size.height*scale)
        image.draw(in: NSRect(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2, width: size.width, height: size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

final class Row: NSTableCellView {
    var paper = NSColor.white
    var usesPicture = false
    override func draw(_ dirtyRect: NSRect) {
        if usesPicture {
            paper.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 2), xRadius: 6, yRadius: 6).fill()
        }
    }
}

final class TodoTableView: NSTableView {
    var menuForEventProvider: ((NSEvent) -> NSMenu?)?
    override func menu(for event: NSEvent) -> NSMenu? {
        if let provider = menuForEventProvider, let customMenu = provider(event) {
            return customMenu
        }
        return super.menu(for: event)
    }
}

// MARK: - Controller

final class Controller: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    let store: Store
    let window: NSWindow
    let surface = Surface()
    let table = TodoTableView()
    let scroll = NSScrollView()
    let header = NSView()
    let tabs = NSSegmentedControl(labels: ["待办", "完成记录"], trackingMode: .selectOne, target: nil, action: nil)
    var pin: ActionButton!, palette: ActionButton!, opacity: ActionButton!, fold: ActionButton!, bottomButton: ActionButton!
    var history = false
    var folded = false
    var expandedHeight: CGFloat = 440
    var saveWork: DispatchWorkItem?
    var completing = [UUID: DispatchWorkItem]()
    var reminderTimer: Timer?
    let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var paper: NSColor { NSColor.hex(store.document.appearance.color) }
    var isDarkBackground: Bool {
        let c = paper.usingColorSpace(.sRGB) ?? NSColor.white
        return c.redComponent*0.299 + c.greenComponent*0.587 + c.blueComponent*0.114 < 0.53
    }
    var ink: NSColor { isDarkBackground ? .white : NSColor.hex("26352B") }

    init(store: Store) {
        self.store = store
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 370, height: 440), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "轻量待办"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 290, height: 150)
        setupWindowRestoration()

        let content = window.contentView!
        ([surface, header] as [NSView]).forEach { $0.translatesAutoresizingMaskIntoConstraints = false; content.addSubview($0) }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            header.topAnchor.constraint(equalTo: content.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 42),
            surface.topAnchor.constraint(equalTo: header.topAnchor),
            surface.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            surface.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        fold = ActionButton(title: "收起", tip: "折叠窗口", accessibility: "收起窗口", action: { [weak self] in self?.toggleFold() })
        pin = ActionButton(title: "", symbol: "pin", tip: "始终置顶", accessibility: "始终置顶", action: { [weak self] in self?.togglePin() })
        opacity = ActionButton(title: "", symbol: "circle.lefthalf.filled", tip: "透明度（整个窗口）", accessibility: "窗口透明度", action: { [weak self] in self?.showOpacity() })
        palette = ActionButton(title: "", symbol: "paintpalette", tip: "底色和背景图片", accessibility: "底色和背景图片", action: { [weak self] in self?.showPalette() })
        let icons = NSStackView(views: [pin, opacity, palette])
        icons.orientation = .horizontal
        icons.spacing = 6
        ([fold!, icons] as [NSView]).forEach { $0.translatesAutoresizingMaskIntoConstraints = false; header.addSubview($0) }
        NSLayoutConstraint.activate([
            fold.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
            fold.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            icons.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            icons.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])

        tabs.selectedSegment = 0
        tabs.target = self
        tabs.action = #selector(changeTab)
        tabs.setAccessibilityLabel("切换待办与完成记录")

        bottomButton = ActionButton(title: "＋ 新增待办", tip: "添加新待办", accessibility: "新增待办", action: { [weak self] in self?.handleBottomButton() })

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 40
        table.intercellSpacing = NSSize(width: 0, height: 1)
        table.selectionHighlightStyle = .none
        table.menuForEventProvider = { [weak self] event in self?.contextMenu(for: event) }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.width = 340
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.delegate = self
        table.dataSource = self
        scroll.documentView = table

        ([tabs, scroll, bottomButton!] as [NSView]).forEach { $0.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview($0) }
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: surface.topAnchor, constant: 46),
            tabs.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 10),
            scroll.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -4),
            scroll.bottomAnchor.constraint(equalTo: bottomButton.topAnchor, constant: -6),
            bottomButton.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 10),
            bottomButton.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -10),
            bottomButton.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -8),
            bottomButton.heightAnchor.constraint(equalToConstant: 28)
        ])

        applyAppearance(loadImage: true)
        DispatchQueue.main.async { [weak self] in
            self?.fireReminders()
            self?.focusRow(0)
        }
    }

    func setupWindowRestoration() {
        window.setFrameAutosaveName("LightTodoNativeWindow")
        if !window.setFrameUsingName("LightTodoNativeWindow") {
            window.center()
        } else {
            ensureWindowOnVisibleScreen()
        }
    }

    func ensureWindowOnVisibleScreen() {
        let frame = window.frame
        let screens = NSScreen.screens
        let isVisible = screens.contains { $0.visibleFrame.intersects(frame) }
        if !isVisible, let screen = NSScreen.main {
            window.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - frame.width/2, y: screen.visibleFrame.midY - frame.height/2))
        }
    }

    func commitEditing() {
        if let textView = window.firstResponder as? NSTextView, let field = textView.delegate as? ItemField {
            if let index = store.document.active.firstIndex(where: { $0.id == field.itemID }) {
                store.document.active[index].text = String(field.stringValue.prefix(10000))
            }
        }
        window.makeFirstResponder(nil)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        history ? store.document.history.count : store.document.active.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if history { return 52 }
        guard row < store.document.active.count else { return 40 }
        let text = store.document.active[row].text + " "
        let occupiedWidth: CGFloat = 104
        let size = (text as NSString).boundingRect(
            with: NSSize(width: max(100, tableView.bounds.width - occupiedWidth), height: 100000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        )
        return max(40, ceil(size.height) + 16)
    }

    func windowDidResize(_ notification: Notification) {
        if !folded {
            expandedHeight = window.frame.height
            window.saveFrame(usingName: "LightTodoNativeWindow")
        }
        table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<numberOfRows(in: table)))
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row index: Int) -> NSView? {
        let cell = Row()
        cell.paper = paper
        cell.usesPicture = surface.picture != nil

        if history {
            guard index < store.document.history.count else { return cell }
            let item = store.document.history[store.document.history.count - 1 - index]
            let stamp = item.completedAt.map { dateFormatter.string(from: $0) } ?? ""
            let text = NSTextField(labelWithString: item.text + (stamp.isEmpty ? "" : "\n" + stamp))
            text.maximumNumberOfLines = 2
            text.lineBreakMode = .byTruncatingTail
            text.textColor = ink.withAlphaComponent(0.88)
            text.font = .systemFont(ofSize: 13)
            text.toolTip = item.text + (stamp.isEmpty ? "" : "\n" + stamp)

            let restore = ActionButton(title: "", symbol: "arrow.uturn.backward", tip: "恢复为待办", accessibility: "恢复待办", action: { [weak self] in
                guard let self = self else { return }
                self.store.restore(item.id)
                self.persist()
                self.history = false
                self.tabs.selectedSegment = 0
                self.bottomButton.title = "＋ 新增待办"
                self.bottomButton.setAccessibilityLabel("新增待办")
                self.table.reloadData()
                if let restoredIndex = self.store.document.active.firstIndex(where: { $0.id == item.id }) {
                    self.focusRow(restoredIndex)
                }
            })
            restore.contentTintColor = ink.withAlphaComponent(0.7)
            layoutHistory(text, restore: restore, in: cell)
        } else {
            guard index < store.document.active.count else { return cell }
            let item = store.document.active[index]
            let isCompleting = completing[item.id] != nil

            let check = ActionButton(title: "", tip: isCompleting ? "点击取消完成" : "完成待办", accessibility: "完成待办", action: { [weak self] in
                self?.toggleComplete(item.id)
            })
            check.setButtonType(.switch)
            check.state = isCompleting ? .on : .off
            check.contentTintColor = isCompleting ? .controlAccentColor : ink

            let field = ItemField()
            field.itemID = item.id
            field.stringValue = item.text
            field.placeholderAttributedString = NSAttributedString(
                string: "点击添加待办",
                attributes: [.foregroundColor: ink.withAlphaComponent(0.42), .font: NSFont.systemFont(ofSize: 14)]
            )
            field.isBordered = false
            field.drawsBackground = false
            field.font = .systemFont(ofSize: 14)
            field.textColor = ink
            field.delegate = self
            field.usesSingleLineMode = false
            field.maximumNumberOfLines = 0
            field.lineBreakMode = .byWordWrapping
            field.cell?.wraps = true
            field.cell?.isScrollable = false
            field.setAccessibilityLabel("待办文本")

            if isCompleting {
                field.isEditable = false
                field.attributedStringValue = NSAttributedString(
                    string: item.text,
                    attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: ink.withAlphaComponent(0.55), .font: NSFont.systemFont(ofSize: 14)]
                )
            }

            var badgeButtons = [NSView]()
            let linkVal = item.link?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let linkBtn = ActionButton(title: "", symbol: "link", tip: linkVal.isEmpty ? "添加网页或本地文件链接" : "打开或修改链接", accessibility: "待办链接", senderAction: { [weak self] button in
                self?.showLinkMenu(item.id, from: button)
            })
            linkBtn.contentTintColor = linkVal.isEmpty ? ink.withAlphaComponent(0.5) : .controlAccentColor
            linkBtn.isEnabled = !isCompleting
            badgeButtons.append(linkBtn)

            let reminderDate = item.reminderAt
            let remBtn = ActionButton(title: "", symbol: reminderDate == nil ? "clock" : "clock.fill", tip: reminderDate.map { "提醒时间: \(dateFormatter.string(from: $0))" } ?? "设置提醒", accessibility: "待办提醒", action: { [weak self] in
                self?.editReminder(item.id)
            })
            remBtn.contentTintColor = reminderDate == nil ? ink.withAlphaComponent(0.5) : .controlAccentColor
            remBtn.isEnabled = !isCompleting
            badgeButtons.append(remBtn)

            layoutActive(field, check: check, badges: badgeButtons, in: cell)
        }
        return cell
    }

    func layoutHistory(_ text: NSView, restore: NSView, in cell: NSView) {
        [text, restore].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview($0) }
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            text.trailingAnchor.constraint(equalTo: restore.leadingAnchor, constant: -6),
            restore.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            restore.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            restore.widthAnchor.constraint(equalToConstant: 24)
        ])
    }

    func layoutActive(_ field: NSView, check: NSView, badges: [NSView], in cell: NSView) {
        [check, field].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview($0) }
        var rules = [
            check.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            check.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 22),
            field.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 6),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ]

        if !badges.isEmpty {
            let stack = NSStackView(views: badges)
            stack.orientation = .horizontal
            stack.spacing = 2
            stack.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(stack)
            rules += [
                field.trailingAnchor.constraint(equalTo: stack.leadingAnchor, constant: -4),
                stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ]
            for b in badges {
                rules.append(b.widthAnchor.constraint(equalToConstant: 22))
            }
        } else {
            rules.append(field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10))
        }
        NSLayoutConstraint.activate(rules)
    }

    // MARK: - Context Menu

    func contextMenu(for event: NSEvent) -> NSMenu? {
        let point = table.convert(event.locationInWindow, from: nil)
        let row = table.row(at: point)
        let menu = NSMenu()

        if history {
            guard row >= 0, row < store.document.history.count else {
                if !store.document.history.isEmpty {
                    menu.addItem(ClosureMenuItem("清空所有完成记录…", action: { [weak self] in self?.promptClearHistory() }))
                    return menu
                }
                return nil
            }
            let item = store.document.history[store.document.history.count - 1 - row]
            menu.addItem(ClosureMenuItem("恢复为待办", action: { [weak self] in
                guard let self = self else { return }
                self.store.restore(item.id)
                self.persist()
                self.history = false
                self.tabs.selectedSegment = 0
                self.bottomButton.title = "＋ 新增待办"
                self.bottomButton.setAccessibilityLabel("新增待办")
                self.table.reloadData()
                if let restoredIndex = self.store.document.active.firstIndex(where: { $0.id == item.id }) {
                    self.focusRow(restoredIndex)
                }
            }))
            menu.addItem(ClosureMenuItem("删除此条记录", action: { [weak self] in
                self?.promptDeleteHistory(item.id)
            }))
            menu.addItem(ClosureMenuItem("复制文本", action: { [weak self] in
                self?.copyText(item.text)
            }))
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("清空所有完成记录…", action: { [weak self] in self?.promptClearHistory() }))
            return menu
        } else {
            guard row >= 0, row < store.document.active.count else { return nil }
            let item = store.document.active[row]
            menu.addItem(ClosureMenuItem("删除此待办", key: "\u{08}", action: { [weak self] in
                self?.promptDeleteItem(item.id)
            }))
            menu.addItem(ClosureMenuItem(completing[item.id] == nil ? "标记为完成" : "取消完成", action: { [weak self] in
                self?.toggleComplete(item.id)
            }))
            menu.addItem(ClosureMenuItem("复制文本", action: { [weak self] in
                self?.copyText(item.text)
            }))
            menu.addItem(.separator())
            if let link = item.link, !link.isEmpty {
                menu.addItem(ClosureMenuItem("打开链接", action: { [weak self] in self?.openLink(item.id) }))
                menu.addItem(ClosureMenuItem("修改网页链接…", action: { [weak self] in self?.editLink(item.id) }))
                menu.addItem(ClosureMenuItem("更改为本地文件…", action: { [weak self] in self?.chooseLinkFile(item.id) }))
                menu.addItem(ClosureMenuItem("移除链接", action: { [weak self] in self?.setLink(nil, for: item.id) }))
            } else {
                menu.addItem(ClosureMenuItem("添加网页链接…", action: { [weak self] in self?.editLink(item.id) }))
                menu.addItem(ClosureMenuItem("关联本地文件…", action: { [weak self] in self?.chooseLinkFile(item.id) }))
            }
            menu.addItem(.separator())
            if item.reminderAt != nil {
                menu.addItem(ClosureMenuItem("修改提醒时间…", action: { [weak self] in self?.editReminder(item.id) }))
                menu.addItem(ClosureMenuItem("取消提醒", action: { [weak self] in
                    guard let self = self, let idx = self.store.document.active.firstIndex(where: { $0.id == item.id }) else { return }
                    self.store.document.active[idx].reminderAt = nil
                    self.persist()
                    self.reloadActiveRow(for: item.id)
                    self.armReminder()
                }))
            } else {
                menu.addItem(ClosureMenuItem("设置提醒…", action: { [weak self] in self?.editReminder(item.id) }))
            }
            return menu
        }
    }

    func promptClearHistory() {
        guard !store.document.history.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "清空完成记录"
        alert.informativeText = "确定要删除所有完成记录吗？此操作无法撤销。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearHistory()
            persist()
            table.reloadData()
        }
    }

    func promptDeleteHistory(_ id: UUID) {
        guard store.document.history.contains(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "删除完成记录"
        alert.informativeText = "确定要永久删除这条完成记录吗？"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.deleteHistory(id)
        persist()
        table.reloadData()
    }

    func promptDeleteItem(_ id: UUID) {
        guard let item = store.document.active.first(where: { $0.id == id }) else { return }
        if item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            deleteItem(id)
            return
        }
        let alert = NSAlert()
        alert.messageText = "删除待办"
        alert.informativeText = "确定要永久删除这条待办吗？它不会进入完成记录。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        deleteItem(id)
    }

    func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func deleteItem(_ id: UUID) {
        completing[id]?.cancel()
        completing.removeValue(forKey: id)
        store.deleteItem(id)
        persist()
        reloadTablePreservingFocus()
        armReminder()
    }

    func toggleComplete(_ id: UUID) {
        if let existing = completing[id] {
            existing.cancel()
            completing.removeValue(forKey: id)
            reloadActiveRow(for: id)
            return
        }
        guard let item = store.document.active.first(where: { $0.id == id }) else { return }
        if item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            deleteItem(id)
            return
        }
        let task = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.completing.removeValue(forKey: id)
            self.store.complete(id)
            self.persist()
            self.reloadTablePreservingFocus()
            self.armReminder()
        }
        completing[id] = task
        reloadActiveRow(for: id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: task)
    }

    func reloadActiveRow(for id: UUID) {
        guard !history, let index = store.document.active.firstIndex(where: { $0.id == id }) else { return }
        table.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: IndexSet(integer: 0))
    }

    func reloadTablePreservingFocus() {
        var activeID: UUID?
        var selectedRange: NSRange?
        if let textView = window.firstResponder as? NSTextView, let field = textView.delegate as? ItemField {
            activeID = field.itemID
            selectedRange = textView.selectedRange()
        }
        table.reloadData()
        if let targetID = activeID {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.history, let idx = self.store.document.active.firstIndex(where: { $0.id == targetID }) else { return }
                if let cell = self.table.view(atColumn: 0, row: idx, makeIfNecessary: true),
                   let targetField = cell.subviews.compactMap({ $0 as? ItemField }).first {
                    self.window.makeFirstResponder(targetField)
                    if let range = selectedRange, let editor = targetField.currentEditor() as? NSTextView, range.location <= (editor.string as NSString).length {
                        editor.setSelectedRange(range)
                    }
                }
            }
        }
    }

    // MARK: - Links and Reminders

    func showLinkMenu(_ id: UUID, from button: ActionButton) {
        guard let item = store.document.active.first(where: { $0.id == id }) else { return }
        let current = item.link?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let menu = NSMenu()
        if !current.isEmpty {
            menu.addItem(ClosureMenuItem("打开链接", action: { [weak self] in self?.openLink(id) }))
        }
        menu.addItem(ClosureMenuItem(current.isEmpty ? "添加网页链接…" : "修改网页链接…", action: { [weak self] in self?.editLink(id) }))
        menu.addItem(ClosureMenuItem("选择本地文件…", action: { [weak self] in self?.chooseLinkFile(id) }))
        if !current.isEmpty {
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("移除链接", action: { [weak self] in self?.setLink(nil, for: id) }))
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    func setLink(_ value: String?, for id: UUID) {
        guard let index = store.document.active.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        store.document.active[index].link = trimmed.isEmpty ? nil : String(trimmed.prefix(4096))
        persist()
        table.reloadData()
    }

    func linkURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            if (scheme == "http" || scheme == "https"), url.host != nil { return url }
            if url.isFileURL, FileManager.default.fileExists(atPath: url.path) { return url }
        }
        let path = (trimmed as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    func editLink(_ id: UUID) {
        guard let item = store.document.active.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "网页链接"
        alert.informativeText = "请输入有效的 http:// 或 https:// 网址："
        let current = item.link ?? ""
        let field = NSTextField(string: current.lowercased().hasPrefix("http") ? current : "")
        field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        field.placeholderString = "https://example.com"
        alert.accessoryView = field
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https"), url.host != nil else {
            showError(NSError(domain: "LightTodo", code: 2, userInfo: [NSLocalizedDescriptionKey: "请输入有效的 http:// 或 https:// 网页地址。"]))
            return
        }
        setLink(value, for: id)
    }

    func chooseLinkFile(_ id: UUID) {
        let picker = NSOpenPanel()
        picker.title = "选择要打开的本地文件"
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        if picker.runModal() == .OK, let url = picker.url {
            setLink(url.path, for: id)
        }
    }

    func openLink(_ id: UUID) {
        guard let value = store.document.active.first(where: { $0.id == id })?.link,
              let url = linkURL(value),
              NSWorkspace.shared.open(url) else {
            showError(NSError(domain: "LightTodo", code: 3, userInfo: [NSLocalizedDescriptionKey: "链接无效，或本地文件已移动。"]))
            return
        }
    }

    func editReminder(_ id: UUID) {
        guard let index = store.document.active.firstIndex(where: { $0.id == id }) else { return }
        let existing = store.document.active[index].reminderAt
        let alert = NSAlert()
        alert.messageText = "设置待办提醒"
        alert.informativeText = "设置本地提醒时间。程序关闭或电脑休眠时不会弹窗，下次打开时会自动补提醒。"
        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
        picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.datePickerStyle = .textFieldAndStepper
        picker.dateValue = existing ?? Date().addingTimeInterval(30 * 60)
        picker.minDate = Date()
        alert.accessoryView = picker
        alert.addButton(withTitle: "保存")
        if existing != nil { alert.addButton(withTitle: "取消提醒") }
        alert.addButton(withTitle: "返回")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            guard picker.dateValue > Date() else {
                showError(NSError(domain: "LightTodo", code: 4, userInfo: [NSLocalizedDescriptionKey: "请选择未来的时间。"]))
                return
            }
            store.document.active[index].reminderAt = picker.dateValue
        } else if existing != nil && response == .alertSecondButtonReturn {
            store.document.active[index].reminderAt = nil
        } else {
            return
        }
        persist()
        table.reloadData()
        armReminder()
    }

    func armReminder() {
        reminderTimer?.invalidate()
        reminderTimer = nil
        guard let next = store.document.active.compactMap({ $0.reminderAt }).min() else { return }
        let timer = Timer(fireAt: max(next, Date().addingTimeInterval(0.1)), interval: 0, target: self, selector: #selector(reminderTimerFired), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        reminderTimer = timer
    }

    @objc func reminderTimerFired() { fireReminders() }

    func fireReminders() {
        let due = store.takeDueReminders(at: Date())
        guard !due.isEmpty else { armReminder(); return }
        persist()
        table.reloadData()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let lines = due.prefix(10).map { item -> String in
            let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmed.isEmpty ? "未命名待办" : String(trimmed.prefix(200))
            return "• " + title + (trimmed.count > 200 ? "…" : "")
        }
        let alert = NSAlert()
        alert.messageText = due.count == 1 ? "待办提醒" : "\(due.count) 条待办提醒"
        alert.informativeText = lines.joined(separator: "\n") + (due.count > 10 ? "\n…" : "")
        alert.addButton(withTitle: "知道了")
        alert.runModal()
        armReminder()
    }

    // MARK: - Text Editing & Delegation

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? ItemField, let index = store.document.active.firstIndex(where: { $0.id == field.itemID }) else { return }
        store.document.active[index].text = String(field.stringValue.prefix(10000))
        scheduleSave()
        table.noteHeightOfRows(withIndexesChanged: IndexSet(integer: index))
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let field = control as? ItemField, !textView.hasMarkedText() else { return false }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            split(field.itemID, text: textView.string, range: textView.selectedRange())
            return true
        }
        if (commandSelector == #selector(NSResponder.deleteBackward(_:)) || commandSelector == #selector(NSResponder.deleteForward(_:))) && textView.string.isEmpty {
            deleteEmpty(field.itemID)
            return true
        }
        return false
    }

    func split(_ id: UUID, text: String, range: NSRange) {
        commitEditing()
        guard let index = store.document.active.firstIndex(where: { $0.id == id }) else { return }
        let value = text as NSString
        guard range.location <= value.length, NSMaxRange(range) <= value.length else { return }
        store.document.active[index].text = value.substring(to: range.location)
        let nextID = store.add(after: id)
        if let nextIndex = store.document.active.firstIndex(where: { $0.id == nextID }) {
            store.document.active[nextIndex].text = value.substring(from: NSMaxRange(range))
        }
        persist()
        table.reloadData()
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.history, let nextIndex = self.store.document.active.firstIndex(where: { $0.id == nextID }) else { return }
            self.table.scrollRowToVisible(nextIndex)
            if let cell = self.table.view(atColumn: 0, row: nextIndex, makeIfNecessary: true),
               let field = cell.subviews.compactMap({ $0 as? ItemField }).first {
                self.window.makeFirstResponder(field)
                (field.currentEditor() as? NSTextView)?.setSelectedRange(NSRange(location: 0, length: 0))
            }
        }
    }

    func deleteEmpty(_ id: UUID) {
        guard let index = store.document.active.firstIndex(where: { $0.id == id }), store.document.active[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        deleteItem(id)
    }

    func scheduleSave() {
        saveWork?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.persist() }
        saveWork = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: task)
    }

    func persist() {
        saveWork?.cancel()
        saveWork = nil
        do { try store.save() } catch { showError(error) }
    }

    func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "操作未完成，原数据已保留"
        alert.runModal()
    }

    func focusRow(_ row: Int) {
        guard !history, row >= 0, row < store.document.active.count else { return }
        table.scrollRowToVisible(row)
        if let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true),
           let field = cell.subviews.compactMap({ $0 as? ItemField }).first {
            window.makeFirstResponder(field)
        }
    }

    func exportData() {
        commitEditing()
        do {
            try store.save()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "LightTodo-tasks.json"
            panel.message = "导出待办数据副本（仅保存在本机）"
            guard panel.runModal() == .OK, let target = panel.url else { return }
            try Data(contentsOf: store.file).write(to: target, options: .atomic)
        } catch {
            showError(error)
        }
    }

    func importData() {
        commitEditing()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "选择由 LightTodo 导出的 JSON 数据文件"
        guard panel.runModal() == .OK, let source = panel.url else { return }

        do {
            let imported = try Store.read(source)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "导入将替换当前待办数据"
            alert.informativeText = "文件包含 \(imported.active.count) 条待办和 \(imported.history.count) 条完成记录。当前数据会先保存为 tasks.backup.json。"
            alert.addButton(withTitle: "导入并替换")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }

            try store.replace(with: imported)
            saveWork?.cancel()
            saveWork = nil
            for task in completing.values { task.cancel() }
            completing.removeAll()
            reminderTimer?.invalidate()
            reminderTimer = nil
            history = false
            tabs.selectedSegment = 0
            bottomButton.title = "＋ 新增待办"
            bottomButton.setAccessibilityLabel("新增待办")
            applyAppearance(loadImage: true)
            table.reloadData()
            armReminder()
            DispatchQueue.main.async { [weak self] in self?.focusRow(0) }
        } catch {
            showError(error)
        }
    }

    func handleBottomButton() {
        if history {
            promptClearHistory()
        } else {
            add(after: nil)
        }
    }

    func add(after id: UUID?) {
        commitEditing()
        let newID = store.add(after: id)
        persist()
        table.reloadData()
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.history, let index = self.store.document.active.firstIndex(where: { $0.id == newID }) else { return }
            self.table.scrollRowToVisible(index)
            if let cell = self.table.view(atColumn: 0, row: index, makeIfNecessary: true),
               let field = cell.subviews.compactMap({ $0 as? ItemField }).first {
                self.window.makeFirstResponder(field)
            }
        }
    }

    func flush() throws {
        commitEditing()
        saveWork?.cancel()
        saveWork = nil
        reminderTimer?.invalidate()
        reminderTimer = nil
        for (id, task) in completing {
            task.cancel()
            store.complete(id)
        }
        completing.removeAll()
        try store.save()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        do {
            try flush()
            return true
        } catch {
            showError(error)
            return false
        }
    }

    @objc func changeTab() {
        commitEditing()
        history = tabs.selectedSegment == 1
        bottomButton.title = history ? "清空完成记录" : "＋ 新增待办"
        bottomButton.setAccessibilityLabel(history ? "清空完成记录" : "新增待办")
        table.reloadData()
        if !history { DispatchQueue.main.async { [weak self] in self?.focusRow(0) } }
    }

    func toggleFold() {
        commitEditing()
        folded.toggle()
        surface.isHidden = folded
        fold.title = folded ? "展开" : "收起"
        fold.setAccessibilityLabel(folded ? "展开窗口" : "收起窗口")
        var frame = window.frame
        let oldHeight = frame.height
        if folded {
            expandedHeight = max(150, oldHeight)
            frame.size.height = 84
            window.minSize.height = 84
        } else {
            frame.size.height = expandedHeight
            window.minSize.height = 150
            if let screen = window.screen ?? NSScreen.main {
                let minY = screen.visibleFrame.minY
                if frame.origin.y < minY {
                    frame.origin.y = minY
                }
            }
        }
        frame.origin.y += oldHeight - frame.height
        window.setFrame(frame, display: true)
    }

    func togglePin() {
        store.document.appearance.pinned.toggle()
        applyAppearance()
        persist()
    }

    func applyAppearance(loadImage: Bool = false) {
        window.backgroundColor = paper
        surface.paper = paper
        window.alphaValue = min(1, max(0.65, store.document.appearance.opacity))
        window.level = store.document.appearance.pinned ? .floating : .normal
        window.appearance = NSAppearance(named: isDarkBackground ? .darkAqua : .aqua)

        fold.contentTintColor = ink
        pin.contentTintColor = ink
        opacity.contentTintColor = ink
        palette.contentTintColor = ink

        pin.image = NSImage(systemSymbolName: store.document.appearance.pinned ? "pin.fill" : "pin", accessibilityDescription: "置顶")
        pin.toolTip = store.document.appearance.pinned ? "取消置顶" : "始终置顶"
        pin.setAccessibilityLabel(store.document.appearance.pinned ? "取消置顶" : "始终置顶")

        if loadImage {
            let name = store.document.appearance.image
            surface.picture = name.hasPrefix("background-") && name == (name as NSString).lastPathComponent ? NSImage(contentsOf: store.directory.appendingPathComponent(name)) : nil
        }
        table.reloadData()
    }

    func menuItem(_ title: String, action: Selector, represented: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = represented
        return item
    }

    func showOpacity() {
        let menu = NSMenu()
        for value in [1.0, 0.9, 0.8, 0.65] {
            let item = menuItem(value == 1 ? "不透明" : "透明 \(Int((1 - value) * 100 + 0.1))%", action: #selector(setOpacity(_:)), represented: value)
            item.state = abs(store.document.appearance.opacity - value) < 0.001 ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: opacity.bounds.height), in: opacity)
    }

    @objc func setOpacity(_ sender: NSMenuItem) {
        store.document.appearance.opacity = sender.representedObject as? Double ?? 1
        applyAppearance()
        persist()
    }

    func showPalette() {
        let menu = NSMenu()
        for (name, color) in [("暖米黄", "FFF9D3"), ("纸白", "F8F8F5"), ("浅绿", "DEEFE0"), ("浅蓝", "DEEBF8"), ("深灰", "303439")] {
            menu.addItem(menuItem(name, action: #selector(setColor(_:)), represented: color))
        }
        menu.addItem(menuItem("自选颜色…", action: #selector(customColor)))
        menu.addItem(.separator())
        menu.addItem(menuItem("选择背景图片…", action: #selector(chooseImage)))
        menu.addItem(menuItem("移除背景图片", action: #selector(clearImage)))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: palette.bounds.height), in: palette)
    }

    @objc func setColor(_ sender: NSMenuItem) {
        store.document.appearance.color = sender.representedObject as? String ?? "FFF9D3"
        applyAppearance()
        persist()
    }

    @objc func customColor() {
        let panel = NSColorPanel.shared
        panel.color = paper
        panel.showsAlpha = false
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.orderFront(nil)
    }

    @objc func colorChanged(_ sender: NSColorPanel) {
        store.document.appearance.color = sender.color.hexString
        applyAppearance()
        scheduleSave()
    }

    @objc func chooseImage() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.png, .jpeg, UTType("public.heic") ?? .image]
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        if picker.runModal() == .OK, let url = picker.url {
            do {
                try store.importImage(url)
                applyAppearance(loadImage: true)
            } catch {
                showError(error)
            }
        }
    }

    @objc func clearImage() {
        let previous = store.document.appearance.image
        store.document.appearance.image = ""
        do {
            try store.save()
            store.removeOwnedImage(previous)
            applyAppearance(loadImage: true)
        } catch {
            store.document.appearance.image = previous
            showError(error)
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: Controller?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LightTodoNativeMac")
            controller = Controller(store: try Store(directory: root))
            controller?.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            controller?.window.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        do {
            try controller?.flush()
            return .terminateNow
        } catch {
            NSAlert(error: error).runModal()
            return .terminateCancel
        }
    }

    @objc func newTodo(_ sender: Any?) {
        controller?.history = false
        controller?.tabs.selectedSegment = 0
        controller?.bottomButton.title = "＋ 新增待办"
        controller?.bottomButton.setAccessibilityLabel("新增待办")
        controller?.table.reloadData()
        controller?.add(after: nil)
    }

    @objc func showActive(_ sender: Any?) {
        guard let controller = controller else { return }
        controller.tabs.selectedSegment = 0
        controller.changeTab()
    }

    @objc func showHistory(_ sender: Any?) {
        guard let controller = controller else { return }
        controller.tabs.selectedSegment = 1
        controller.changeTab()
    }

    @objc func togglePinShortcut(_ sender: Any?) { controller?.togglePin() }
    @objc func clearHistory(_ sender: Any?) { controller?.promptClearHistory() }
    @objc func importData(_ sender: Any?) { controller?.importData() }
    @objc func exportData(_ sender: Any?) { controller?.exportData() }
}

// MARK: - Self Test

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw NSError(domain: "LightTodoTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

func selfTest(_ directory: URL) throws {
    let store = try Store(directory: directory)
    try check(store.document.active.count == 1 && store.document.history.isEmpty, "clean startup")

    let first = store.document.active[0].id
    store.document.active[0].text = "中文与 English 测试"
    let second = store.add(after: first)
    try check(store.document.active[1].id == second, "add position")
    store.document.active[1].text = "第二条测试待办"
    try store.save()

    // 验证向后兼容与鲁棒性：允许旧数据缺少新字段，拒绝会破坏数据一致性的重复 UUID
    let olderJSON = """
    {"active":[{"id":"\(UUID().uuidString)","text":"旧数据1"},{"id":"\(UUID().uuidString)","text":"旧数据2"}],"history":[]}
    """
    let olderFile = directory.appendingPathComponent("older.json")
    try Data(olderJSON.utf8).write(to: olderFile)
    let olderDoc = try Store.read(olderFile)
    try check(olderDoc.active.count == 2 && olderDoc.appearance.color == "FFF9D3", "backward compatibility with missing appearance/reminder/link fields")
    try FileManager.default.removeItem(at: olderFile)

    let duplicateID = UUID().uuidString
    let duplicateJSON = """
    {"active":[{"id":"\(duplicateID)","text":"条目1"},{"id":"\(duplicateID)","text":"条目2"}],"history":[],"appearance":{"color":"FFF9D3","opacity":1.0,"pinned":false,"image":""}}
    """
    let duplicateFile = directory.appendingPathComponent("duplicate.json")
    try Data(duplicateJSON.utf8).write(to: duplicateFile)
    var duplicateRejected = false
    do { _ = try Store.read(duplicateFile) } catch { duplicateRejected = true }
    try check(duplicateRejected, "reject duplicate UUIDs without silently rewriting data")
    try FileManager.default.removeItem(at: duplicateFile)

    let invalidAppearanceJSON = """
    {"active":[{"id":"\(UUID().uuidString)","text":"外观异常"}],"history":[],"appearance":{"color":"not-a-color","opacity":99,"pinned":false,"image":"../private.jpg"}}
    """
    let invalidAppearanceFile = directory.appendingPathComponent("invalid-appearance.json")
    try Data(invalidAppearanceJSON.utf8).write(to: invalidAppearanceFile)
    var invalidAppearanceRejected = false
    do { _ = try Store.read(invalidAppearanceFile) } catch { invalidAppearanceRejected = true }
    try check(invalidAppearanceRejected, "reject malformed appearance values")
    try FileManager.default.removeItem(at: invalidAppearanceFile)

    let scaleFile = directory.appendingPathComponent("scale.json")
    let scaleDocument = Document(
        active: (0..<150).map { Todo(text: "待办 \($0)") },
        history: (0..<1000).map { Todo(text: "完成 \($0)", completedAt: Date()) }
    )
    try JSONEncoder().encode(scaleDocument).write(to: scaleFile)
    let scaleReload = try Store.read(scaleFile)
    try check(scaleReload.active.count == 150 && scaleReload.history.count == 1000, "150 active and 1000 history entries")
    try FileManager.default.removeItem(at: scaleFile)

    // 导入替换：先备份原数据，接受有效文件，并清除目标电脑上不存在的背景图片引用
    let importDirectory = directory.appendingPathComponent("import-replace", isDirectory: true)
    let importStore = try Store(directory: importDirectory)
    importStore.document.active[0].text = "导入前数据"
    try importStore.save()
    let importFile = directory.appendingPathComponent("import.json")
    let importedDocument = Document(
        active: [Todo(text: "导入后的待办", reminderAt: Date().addingTimeInterval(300), link: "https://example.com/import")],
        history: [Todo(text: "导入的完成记录", completedAt: Date())],
        appearance: Appearance(color: "E8F2FF", opacity: 0.9, pinned: true, image: "background-missing.png")
    )
    try JSONEncoder().encode(importedDocument).write(to: importFile)
    try importStore.replace(with: Store.read(importFile))
    try check(importStore.document.active.first?.text == "导入后的待办" && importStore.document.history.count == 1, "import replaces active and history data")
    try check(importStore.document.appearance.image.isEmpty, "import clears unavailable background image reference")
    let importBackup = try Store.read(importStore.backupFile)
    try check(importBackup.active.first?.text == "导入前数据", "import preserves previous data as backup")
    try FileManager.default.removeItem(at: importFile)

    let controller = Controller(store: store)
    controller.window.makeKeyAndOrderFront(nil)

    let blank = store.add(after: nil)
    controller.toggleComplete(blank)
    try check(!store.document.active.contains(where: { $0.id == blank }) && store.document.history.isEmpty, "empty item removes immediately without history")

    // 测试非空删除（取消待办）
    let toDelete = store.add(after: nil)
    guard let delIdx = store.document.active.firstIndex(where: { $0.id == toDelete }) else { throw TodoError.invalidData }
    store.document.active[delIdx].text = "不做了取消掉"
    controller.deleteItem(toDelete)
    try check(!store.document.active.contains(where: { $0.id == toDelete }) && store.document.history.isEmpty, "non-empty item deletion without history")

    // 测试拆分
    let temporary = store.add(after: nil)
    controller.split(temporary, text: "前半后半", range: NSRange(location: 2, length: 0))
    try check(store.document.active.suffix(2).map { $0.text } == ["前半", "后半"], "caret split")
    store.document.active.removeLast(2)
    controller.table.reloadData()

    let empty = store.add(after: nil)
    controller.deleteEmpty(empty)
    try check(store.document.active.count == 2, "delete empty item")

    // 测试即时反悔（Undo complete during countdown）
    controller.toggleComplete(first)
    try check(controller.completing[first] != nil, "completion feedback countdown")
    controller.toggleComplete(first) // 再次点击取消完成
    try check(controller.completing[first] == nil, "undo completion during countdown")

    // 重新完成并在倒计时后移入 history
    controller.toggleComplete(first)
    RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    try check(store.document.history.count == 1 && store.document.history[0].completedAt != nil, "delayed completion to history")

    store.restore(first)
    try check(store.document.history.isEmpty && store.document.active.first(where: { $0.id == first })?.completedAt == nil, "restore removes history and timestamp")

    // 链接与提醒
    guard let firstIndex = store.document.active.firstIndex(where: { $0.id == first }) else { throw TodoError.invalidData }
    store.document.active[firstIndex].link = "https://example.com/lighttodo"
    store.document.active[firstIndex].reminderAt = Date().addingTimeInterval(600)
    try store.save()

    let featureReload = try Store(directory: directory)
    try check(featureReload.document.active.first(where: { $0.id == first })?.link == "https://example.com/lighttodo", "link persistence")
    try check(featureReload.document.active.first(where: { $0.id == first })?.reminderAt != nil, "reminder persistence")
    try check(controller.linkURL("https://example.com/lighttodo") != nil, "web link validation")
    controller.copyText("复制测试")
    try check(NSPasteboard.general.string(forType: .string) == "复制测试", "copy todo text")

    let localTarget = directory.appendingPathComponent("link-target.txt")
    try Data("local".utf8).write(to: localTarget)
    try check(controller.linkURL(localTarget.path)?.isFileURL == true, "local link validation")
    try FileManager.default.removeItem(at: localTarget)

    try check(store.takeDueReminders(at: Date()).isEmpty, "future reminder waits")
    try check(store.takeDueReminders(at: Date().addingTimeInterval(601)).count == 1 && store.takeDueReminders(at: Date().addingTimeInterval(602)).isEmpty, "reminder fires once")

    store.document.active[firstIndex].reminderAt = Date().addingTimeInterval(600)
    store.complete(first)
    try check(store.document.history.first(where: { $0.id == first })?.reminderAt == nil, "completion cancels reminder")
    store.restore(first)

    // 历史管理：清空历史
    let historyOnly = store.add(after: nil)
    guard let historyIndex = store.document.active.firstIndex(where: { $0.id == historyOnly }) else { throw TodoError.invalidData }
    store.document.active[historyIndex].text = "仅用于清空历史测试"
    store.complete(historyOnly)
    try check(store.document.history.count == 1, "history has item")
    store.clearHistory()
    try check(store.document.history.isEmpty, "clear history")

    // 外观与折叠
    controller.togglePin()
    try check(controller.window.level == .floating, "pin")
    store.document.appearance.opacity = 0.8
    controller.applyAppearance()
    try check(abs(controller.window.alphaValue - 0.8) < 0.01, "opacity")
    controller.toggleFold()
    try check(controller.surface.isHidden, "fold")
    controller.toggleFold()

    let image = NSImage(size: NSSize(width: 2000, height: 1200))
    image.lockFocus()
    NSColor.systemTeal.setFill()
    NSRect(x: 0, y: 0, width: 2000, height: 1200).fill()
    NSColor.systemOrange.setFill()
    NSBezierPath(ovalIn: NSRect(x: 1200, y: 100, width: 600, height: 600)).fill()
    image.unlockFocus()
    let input = directory.appendingPathComponent("test-input.png")
    guard let imageData = image.tiffRepresentation else { throw TodoError.invalidImage }
    try imageData.write(to: input)
    try store.importImage(input)
    controller.applyAppearance(loadImage: true)
    try check(controller.surface.picture != nil, "image loaded")
    try FileManager.default.removeItem(at: input)

    try controller.flush()
    let reopened = try Store(directory: directory)
    try check(reopened.document.appearance.pinned && reopened.document.active.count == 2, "settings persistence")

    controller.window.alphaValue = 1
    controller.window.contentView?.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    if let view = controller.window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: directory.appendingPathComponent("preview.png"))
        }
    }
    controller.window.close()

    // 容错与恢复测试：主文件损坏时自愈
    try store.save()
    try Data("broken".utf8).write(to: store.file)
    let recovered = try Store(directory: directory)
    try check(recovered.document.active.count == 2, "backup recovery")
    let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    try check(files.contains(where: { $0.hasPrefix("tasks.damaged-") }), "damaged original preserved")

    try Data("PASS: native launch, add, delayed check-off, undo complete, history, restore, clear history, delete item, reminder, link, copy, import, pin, opacity, fold, image, persistence, scale, validation, backup recovery\n".utf8).write(to: directory.appendingPathComponent("result.txt"))
    print("PASS: native app smoke and data tests")
}

// MARK: - Entry Point

let application = NSApplication.shared
application.setActivationPolicy(.regular)

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--self-test" {
    do {
        application.finishLaunching()
        try selfTest(URL(fileURLWithPath: CommandLine.arguments[2]))
        exit(0)
    } catch {
        fputs("FAIL: \(error)\n", stderr)
        exit(1)
    }
}

if let bundleID = Bundle.main.bundleIdentifier,
   let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
    existing.activate(options: [.activateIgnoringOtherApps])
    exit(0)
}

let delegate = AppDelegate()
application.delegate = delegate

let mainMenu = NSMenu()
let appItem = NSMenuItem()
let appMenu = NSMenu()
appMenu.addItem(withTitle: "关于轻量待办", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
appMenu.addItem(.separator())
appMenu.addItem(withTitle: "隐藏轻量待办", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
let hideOthers = appMenu.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
hideOthers.keyEquivalentModifierMask = [.command, .option]
appMenu.addItem(withTitle: "全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
appMenu.addItem(.separator())
appMenu.addItem(withTitle: "退出轻量待办", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appItem.submenu = appMenu
mainMenu.addItem(appItem)

let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
let editMenu = NSMenu(title: "编辑")
for (name, selector, key) in [
    ("撤销", Selector(("undo:")), "z"),
    ("重做", Selector(("redo:")), "z"),
    ("剪切", #selector(NSText.cut(_:)), "x"),
    ("复制", #selector(NSText.copy(_:)), "c"),
    ("粘贴", #selector(NSText.paste(_:)), "v"),
    ("全选", #selector(NSText.selectAll(_:)), "a")
] {
    let item = editMenu.addItem(withTitle: name, action: selector, keyEquivalent: key)
    if name == "重做" { item.keyEquivalentModifierMask = [.command, .shift] }
}
editItem.submenu = editMenu
mainMenu.addItem(editItem)

let todoItem = NSMenuItem(title: "待办", action: nil, keyEquivalent: "")
let todoMenu = NSMenu(title: "待办")
todoMenu.addItem(withTitle: "新增待办", action: #selector(AppDelegate.newTodo(_:)), keyEquivalent: "n")
todoMenu.addItem(.separator())
todoMenu.addItem(withTitle: "待办列表", action: #selector(AppDelegate.showActive(_:)), keyEquivalent: "1")
todoMenu.addItem(withTitle: "完成记录", action: #selector(AppDelegate.showHistory(_:)), keyEquivalent: "2")
let pinShortcut = todoMenu.addItem(withTitle: "切换置顶", action: #selector(AppDelegate.togglePinShortcut(_:)), keyEquivalent: "p")
pinShortcut.keyEquivalentModifierMask = [.command, .shift]
todoMenu.addItem(.separator())
todoMenu.addItem(withTitle: "清空完成记录…", action: #selector(AppDelegate.clearHistory(_:)), keyEquivalent: "")
todoMenu.addItem(withTitle: "导入待办数据…", action: #selector(AppDelegate.importData(_:)), keyEquivalent: "")
todoMenu.addItem(withTitle: "导出待办数据…", action: #selector(AppDelegate.exportData(_:)), keyEquivalent: "")
todoItem.submenu = todoMenu
mainMenu.addItem(todoItem)
application.mainMenu = mainMenu

application.run()
