import UIKit
import Flutter

// A Liquid Glass capsule holding a column (or row) of icon buttons. It is the
// building block of the iPhone Duo trailing bar, where the system shows each
// group of toolbar items, and the tab bar, as one glass capsule.

// MARK: - Factory
class iOS26GlassCapsuleFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return iOS26GlassCapsuleView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

// MARK: - Container
private class GlassCapsuleContainer: UIView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

// A menu on an interactive glass effect resets the capsule to a rectangle.
// `cornerConfiguration` is what the material keeps; reapply it once UIKit has
// finished writing the shape.
private class GlassCapsuleButton: UIButton {
    var onMenuEnd: (() -> Void)?

    /// The item's `id`, when it has one. Buttons are matched by it across
    /// updates instead of being rebuilt.
    var itemId: String?
    /// Symbol currently drawn by `symbolView`; empty when it draws none.
    var symbolName = ""
    /// Alpha the button settles at once an insert or remove animation ends.
    var restingAlpha: CGFloat = 1

    /// Draws the symbol of an item with an `id`. A configuration image cannot
    /// run the symbol content transition, so the symbol lives in a view of
    /// its own.
    private(set) lazy var symbolView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .center
        view.isUserInteractionEnabled = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: centerXAnchor),
            view.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        return view
    }()
    private var hasSymbolView = false

    /// Shows `image` (already sized and tinted), with the replace transition
    /// when asked to and available.
    func showSymbol(_ image: UIImage, name: String, animated: Bool) {
        hasSymbolView = true
        symbolView.isHidden = false
        if #available(iOS 17.0, *), animated {
            symbolView.setSymbolImage(image, contentTransition: .replace)
        } else {
            symbolView.image = image
        }
        symbolName = name
    }

    func hideSymbol() {
        guard hasSymbolView else { return }
        symbolView.isHidden = true
        symbolView.image = nil
        symbolName = ""
    }

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        super.contextMenuInteraction(
            interaction, willEndFor: configuration, animator: animator)
        guard let onMenuEnd else { return }
        if let animator {
            animator.addCompletion { onMenuEnd() }
        } else {
            onMenuEnd()
        }
    }
}

// MARK: - Platform View
class iOS26GlassCapsuleView: NSObject, FlutterPlatformView {
    private let container = GlassCapsuleContainer()
    private let effectView = UIVisualEffectView()
    private let selectionView = UIView()
    private let stack = UIStackView()
    private var channel: FlutterMethodChannel

    private var items: [[String: Any]] = []
    private var buttons: [GlassCapsuleButton] = []
    private var generation = 0
    private var badges: [Int: UILabel] = [:]
    private var selectedIndex: Int?
    private var tint: UIColor?
    private var inset: CGFloat = 0
    private var stackTop: NSLayoutConstraint?
    private var stackBottom: NSLayoutConstraint?
    private var stackLeading: NSLayoutConstraint?
    private var stackTrailing: NSLayoutConstraint?
    private var horizontal = false
    private var imageCache: [String: UIImage] = [:]
    private var widthConstraints: [NSLayoutConstraint] = []
    /// Point size and weight of every symbol. 17 / medium unless the
    /// creation params say otherwise.
    private var symbolPointSize: CGFloat = 17
    private var symbolImageWeight: UIImage.SymbolWeight = .medium

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/ios26_glass_capsule_\(viewId)",
            binaryMessenger: messenger
        )
        super.init()

        container.frame = frame
        container.backgroundColor = .clear

        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect()
            glass.isInteractive = true
            effectView.effect = glass
        } else {
            effectView.effect = UIBlurEffect(style: .systemThinMaterial)
        }
        effectView.clipsToBounds = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(effectView)

        selectionView.backgroundColor = UIColor.label.withAlphaComponent(0.1)
        selectionView.isUserInteractionEnabled = false
        selectionView.isHidden = true
        effectView.contentView.addSubview(selectionView)

        stack.axis = .vertical
        stack.distribution = .fillEqually
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        effectView.contentView.addSubview(stack)

        let top = stack.topAnchor.constraint(equalTo: effectView.contentView.topAnchor)
        let bottom = stack.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor)
        let leading = stack.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor)
        let trailing = stack.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor)
        stackTop = top
        stackBottom = bottom
        stackLeading = leading
        stackTrailing = trailing
        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: container.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            leading,
            trailing,
            top,
            bottom,
        ])

        container.onLayout = { [weak self] in self?.layoutChrome(animated: false) }

        if let params = args as? [String: Any] {
            apply(params)
        }

        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return result(nil) }
            switch call.method {
            case "update":
                if let params = call.arguments as? [String: Any] {
                    self.apply(params)
                }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    func view() -> UIView { container }

    // MARK: Content

    private func apply(_ params: [String: Any]) {
        if let dark = params["isDark"] as? Bool {
            container.overrideUserInterfaceStyle = dark ? .dark : .light
        }
        if let n = params["tint"] as? NSNumber {
            tint = Self.colorFromARGB(n.intValue)
        } else if params.keys.contains("items") {
            tint = nil
        }
        if params.keys.contains("items") {
            horizontal = (params["axis"] as? String) == "horizontal"
            stack.axis = horizontal ? .horizontal : .vertical
        }
        if let value = params["inset"] as? NSNumber {
            inset = CGFloat(truncating: value)
        }
        // The inset applies along the main axis only.
        stackTop?.constant = horizontal ? 0 : inset
        stackBottom?.constant = horizontal ? 0 : -inset
        stackLeading?.constant = horizontal ? inset : 0
        stackTrailing?.constant = horizontal ? -inset : 0

        if let size = params["symbolSize"] as? NSNumber {
            symbolPointSize = CGFloat(truncating: size)
        } else {
            symbolPointSize = 17
        }
        if let weight = params["symbolWeight"] as? NSNumber {
            symbolImageWeight = .fromFontWeight(weight.intValue)
        } else {
            symbolImageWeight = .medium
        }

        let newSelected = (params["selectedIndex"] as? NSNumber)?.intValue
        let selectionChanged = newSelected != selectedIndex
        selectedIndex = newSelected

        var transition: ItemTransition?
        if let newItems = params["items"] as? [[String: Any]] {
            let previousItems = items
            items = newItems
            if let ids = Self.itemIds(newItems) {
                // Every item has an id: keep the buttons that are still
                // there, so a symbol change can play the system transition
                // and added or removed items animate.
                if ids == Self.itemIds(previousItems), buttons.count == newItems.count {
                    updateButtonsInPlace(previous: previousItems)
                } else {
                    transition = reconcileButtons()
                }
            } else {
                // A widthFactor change is the heart closing with the title.
                // The buttons stay; only their widths move. Rebuilding would
                // pop the icon out and start over.
                let same = (withoutWidthFactor(newItems) as NSArray)
                    .isEqual(to: withoutWidthFactor(previousItems))
                if !same || buttons.count != newItems.count {
                    rebuildButtons()
                }
            }
        }
        refreshAppearance()
        applyWidthFactors()
        transition?.run()
        container.setNeedsLayout()
        layoutChrome(animated: selectionChanged && !buttons.isEmpty)
    }

    /// Item maps with `widthFactor` removed, so a factor-only update compares
    /// equal and does not rebuild the buttons.
    private func withoutWidthFactor(_ source: [[String: Any]]) -> [[String: Any]] {
        source.map { item in
            var copy = item
            copy.removeValue(forKey: "widthFactor")
            return copy
        }
    }

    /// While every factor is 1 the row is split equally, as before. A factor
    /// below 1 (the closing heart) takes `actionPitch * factor` and fades by
    /// the same amount; the other buttons keep the width they have in a
    /// capsule of only those full buttons. Pitch matches
    /// `IOS26GlassCapsule.actionPitch`.
    private func applyWidthFactors() {
        NSLayoutConstraint.deactivate(widthConstraints)
        widthConstraints = []
        let reset = {
            self.stack.distribution = .fillEqually
            for button in self.buttons {
                button.alpha = 1
                button.isUserInteractionEnabled = true
            }
        }
        guard horizontal, buttons.count == items.count, !buttons.isEmpty else {
            reset()
            return
        }
        let factors: [CGFloat] = items.map { item in
            min(1, max(0, CGFloat((item["widthFactor"] as? NSNumber)?.doubleValue ?? 1)))
        }
        guard factors.contains(where: { $0 < 0.999 }) else {
            reset()
            return
        }
        stack.distribution = .fill
        let fullCount = factors.filter { $0 >= 0.999 }.count
        let actionPitch: CGFloat = 52
        let fullTotal = fullCount > 0
            ? 48 + CGFloat(fullCount - 1) * actionPitch
            : 0
        let fullEach = fullCount > 0 ? fullTotal / CGFloat(fullCount) : 0
        for (index, button) in buttons.enumerated() {
            let factor = factors[index]
            let full = factor >= 0.999
            let width = full ? fullEach : actionPitch * factor
            let constraint = button.widthAnchor.constraint(equalToConstant: width)
            constraint.isActive = true
            widthConstraints.append(constraint)
            button.alpha = full ? 1 : factor
            button.isUserInteractionEnabled = factor > 0.01
        }
    }

    /// The `id` of every item, or nil if one lacks it or two share it.
    private static func itemIds(_ source: [[String: Any]]) -> [String]? {
        var ids: [String] = []
        for item in source {
            guard let id = item["id"] as? String, !id.isEmpty else { return nil }
            ids.append(id)
        }
        return Set(ids).count == ids.count ? ids : nil
    }

    private func rebuildButtons() {
        NSLayoutConstraint.deactivate(widthConstraints)
        widthConstraints = []
        NSLayoutConstraint.deactivate(selectionConstraints)
        selectionConstraints = []
        selectionAnchor = nil
        buttons.forEach { $0.removeFromSuperview() }
        buttons = []
        badges.values.forEach { $0.removeFromSuperview() }
        badges = [:]

        for (index, item) in items.enumerated() {
            let button = makeButton(for: item, index: index)
            stack.addArrangedSubview(button)
            buttons.append(button)
        }
        rebuildBadges()
    }

    private func makeButton(for item: [String: Any], index: Int) -> GlassCapsuleButton {
        let button = GlassCapsuleButton(type: .system)
        configureAction(of: button, item: item, index: index)
        return button
    }

    /// Tap target or menu, tag and accessibility label of a button.
    private func configureAction(
        of button: GlassCapsuleButton, item: [String: Any], index: Int
    ) {
        button.tag = index
        button.itemId = item["id"] as? String
        button.removeTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
        if let entries = item["menu"] as? [[String: Any]] {
            // The overflow control: a menu of the items that did not fit.
            button.showsMenuAsPrimaryAction = true
            button.onMenuEnd = { [weak self] in self?.restoreCapsuleShape() }
            if #available(iOS 16.0, *) {
                // Keep the given order; with .automatic UIKit reverses the
                // menu depending on where the button sits (the Duo's cover
                // display versus its open display).
                button.preferredMenuElementOrder = .fixed
            }
            button.menu = UIMenu(children: entries.map { entry in
                let id = (entry["id"] as? NSNumber)?.intValue ?? -1
                let symbol = entry["symbol"] as? String
                let destructive = (entry["destructive"] as? Bool) ?? false
                return UIAction(
                    title: entry["title"] as? String ?? "",
                    image: symbol.flatMap { UIImage(systemName: $0) ?? UIImage(named: $0) },
                    attributes: destructive ? .destructive : []
                ) { [weak self] _ in
                    self?.channel.invokeMethod("onMenuItemTapped", arguments: ["id": id])
                    self?.restoreCapsuleShape()
                }
            })
        } else {
            button.showsMenuAsPrimaryAction = false
            button.menu = nil
            button.onMenuEnd = nil
            button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
        }
        button.accessibilityLabel = item["label"] as? String
    }

    /// One count bubble per item that has a badge, tied to its button.
    private func rebuildBadges() {
        badges.values.forEach { $0.removeFromSuperview() }
        badges = [:]
        for (index, item) in items.enumerated() where index < buttons.count {
            let button = buttons[index]
            if let count = (item["badge"] as? NSNumber)?.intValue, count > 0 {
                let badge = UILabel()
                badge.text = count > 99 ? "99+" : "\(count)"
                badge.font = .systemFont(ofSize: 11, weight: .semibold)
                badge.textColor = .white
                badge.textAlignment = .center
                badge.backgroundColor = .systemRed
                badge.clipsToBounds = true
                badge.isUserInteractionEnabled = false
                badge.layer.cornerRadius = 9
                badge.translatesAutoresizingMaskIntoConstraints = false
                // Above the glass, so the capsule's rounded clipping does not
                // cut it, and tied to its button so it follows every layout.
                container.addSubview(badge)
                let width = badge.widthAnchor.constraint(
                    equalToConstant: max(18, badge.intrinsicContentSize.width + 8))
                NSLayoutConstraint.activate([
                    badge.heightAnchor.constraint(equalToConstant: 18),
                    width,
                    badge.centerXAnchor.constraint(equalTo: button.centerXAnchor, constant: 11),
                    badge.centerYAnchor.constraint(equalTo: button.centerYAnchor, constant: -12),
                ])
                badges[index] = badge
            }
        }
    }

    // MARK: Buttons kept by id

    /// Same ids in the same order: nothing is added or removed, so each
    /// button only takes the new item (symbol, label, tint come with
    /// `refreshAppearance`).
    private func updateButtonsInPlace(previous: [[String: Any]]) {
        for (index, item) in items.enumerated() {
            configureAction(of: buttons[index], item: item, index: index)
        }
        let badgeCounts = { (source: [[String: Any]]) in
            source.map { ($0["badge"] as? NSNumber)?.intValue ?? 0 }
        }
        if badgeCounts(items) != badgeCounts(previous) {
            rebuildBadges()
        }
    }

    /// The ids changed. Buttons whose id is still there are reused; new ones
    /// are made and removed ones are kept until they have faded out. The
    /// returned transition runs once the appearance and widths are applied.
    private func reconcileButtons() -> ItemTransition {
        let current = stack.arrangedSubviews.compactMap { $0 as? GlassCapsuleButton }
        var pool: [String: GlassCapsuleButton] = [:]
        for button in buttons + current {
            if let id = button.itemId, pool[id] == nil { pool[id] = button }
        }

        let animate = !current.isEmpty
        var desired: [GlassCapsuleButton] = []
        var fresh: [GlassCapsuleButton] = []
        for (index, item) in items.enumerated() {
            let button: GlassCapsuleButton
            if let id = item["id"] as? String, let existing = pool[id] {
                button = existing
            } else {
                button = GlassCapsuleButton(type: .system)
                fresh.append(button)
            }
            configureAction(of: button, item: item, index: index)
            desired.append(button)
        }
        let removed = current.filter { old in !desired.contains { $0 === old } }
        for button in removed { button.tag = -1 }
        buttons = desired

        NSLayoutConstraint.deactivate(selectionConstraints)
        selectionConstraints = []
        selectionAnchor = nil

        generation += 1
        return ItemTransition(
            view: self, token: generation, animate: animate,
            desired: desired, fresh: fresh, removed: removed, current: current)
    }

    /// Inserts and removals of buttons, animated like the heart closing: the
    /// stack collapses a hidden arranged subview, so fading and hiding it in
    /// an animation block shrinks the row smoothly.
    private struct ItemTransition {
        let view: iOS26GlassCapsuleView
        let token: Int
        let animate: Bool
        let desired: [GlassCapsuleButton]
        let fresh: [GlassCapsuleButton]
        let removed: [GlassCapsuleButton]
        let current: [GlassCapsuleButton]

        func run() {
            let view = self.view
            for button in desired { button.restingAlpha = button.alpha }
            guard animate else {
                view.arrange(desired)
                view.rebuildBadges()
                return
            }
            let order = view.mergedOrder(desired: desired, removed: removed, current: current)
            UIView.performWithoutAnimation {
                for button in fresh {
                    button.alpha = 0
                    button.isHidden = true
                }
                view.arrange(order)
                view.rebuildBadges()
                view.container.layoutIfNeeded()
            }
            UIView.animate(
                withDuration: 0.25, delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
                animations: {
                    for button in removed {
                        button.alpha = 0
                        button.isHidden = true
                    }
                    for button in desired {
                        button.alpha = button.restingAlpha
                        button.isHidden = false
                    }
                    view.container.layoutIfNeeded()
                },
                completion: { _ in
                    guard token == view.generation else { return }
                    for button in removed where !view.buttons.contains(where: { $0 === button }) {
                        view.stack.removeArrangedSubview(button)
                        button.removeFromSuperview()
                    }
                })
        }
    }

    /// `desired` order, with each retiring button left in the hole it
    /// occupied so the stack can collapse it instead of popping it out.
    private func mergedOrder(
        desired: [GlassCapsuleButton],
        removed: [GlassCapsuleButton],
        current: [GlassCapsuleButton]
    ) -> [GlassCapsuleButton] {
        var order = desired
        let leaving = removed.sorted { a, b in
            let ia = current.firstIndex(where: { $0 === a }) ?? 0
            let ib = current.firstIndex(where: { $0 === b }) ?? 0
            return ia < ib
        }
        for button in leaving {
            guard let oldIndex = current.firstIndex(where: { $0 === button }) else { continue }
            var insertAt = 0
            if oldIndex > 0 {
                for previous in current[..<oldIndex].reversed() {
                    if let index = order.firstIndex(where: { $0 === previous }) {
                        insertAt = index + 1
                        break
                    }
                }
            }
            order.insert(button, at: min(insertAt, order.count))
        }
        return order
    }

    private func arrange(_ order: [GlassCapsuleButton]) {
        for (index, button) in order.enumerated() {
            let inPlace = stack.arrangedSubviews.count > index
                && stack.arrangedSubviews[index] === button
            if inPlace { continue }
            stack.insertArrangedSubview(button, at: min(index, stack.arrangedSubviews.count))
        }
        let keep = Set(order.map { ObjectIdentifier($0) })
        for case let button as GlassCapsuleButton in Array(stack.arrangedSubviews)
            where !keep.contains(ObjectIdentifier(button)) {
            stack.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
    }

    private func refreshAppearance() {
        for (index, button) in buttons.enumerated() {
            let item = items[index]
            let selected = index == selectedIndex
            let itemTint = (item["tint"] as? NSNumber).map { Self.colorFromARGB($0.intValue) }

            var config = UIButton.Configuration.plain()
            config.contentInsets = .zero
            let symbolConfiguration = UIImage.SymbolConfiguration(
                pointSize: symbolPointSize, weight: symbolImageWeight)
            config.preferredSymbolConfigurationForImage = symbolConfiguration

            let color: UIColor
            if selectedIndex != nil {
                // A tab: tinted while selected, label colour otherwise.
                color = selected ? (itemTint ?? tint ?? .systemBlue) : .label
            } else {
                color = itemTint ?? tint ?? .label
            }

            let symbol = Self.symbolName(for: item, selected: selected)
            if item["id"] is String, let symbol,
               let glyph = UIImage(systemName: symbol) ?? UIImage(named: symbol) {
                // An item with an id keeps its button, so its symbol is drawn
                // by the button's own view and swaps with the replace
                // transition. The size and tint are baked into the image: a
                // tinted symbol no longer follows the view's configuration.
                let sized = glyph.applyingSymbolConfiguration(symbolConfiguration) ?? glyph
                let presented = sized.withTintColor(color, renderingMode: .alwaysOriginal)
                let changed = !button.symbolName.isEmpty && button.symbolName != symbol
                button.showSymbol(presented, name: symbol, animated: changed)
            } else if let image = image(for: item, selected: selected, index: index) {
                button.hideSymbol()
                config.image = image
            } else if let title = item["title"] as? String {
                var text = AttributedString(title)
                text.font = .systemFont(ofSize: 12, weight: .medium)
                config.attributedTitle = text
                button.hideSymbol()
            } else {
                button.hideSymbol()
            }
            config.baseForegroundColor = color
            button.configuration = config
            button.tintColor = color
        }
    }

    /// An SF Symbol (or asset catalog image) is tinted; a picture from the
    /// Flutter assets, a file or the network keeps its colours, as an avatar.
    private func image(for item: [String: Any], selected: Bool, index: Int) -> UIImage? {
        let symbol = Self.symbolName(for: item, selected: selected)
        if let symbol = symbol, !symbol.isEmpty {
            return UIImage(systemName: symbol) ?? UIImage(named: symbol)
        }
        if let asset = item["asset"] as? String, !asset.isEmpty {
            let key = FlutterDartProject.lookupKey(forAsset: asset)
            if let path = Bundle.main.path(forResource: key, ofType: nil),
               let image = UIImage(contentsOfFile: path) {
                return Self.avatar(image)
            }
        }
        if let file = item["file"] as? String, !file.isEmpty,
           let image = UIImage(contentsOfFile: file) {
            return Self.avatar(image)
        }
        if let network = item["network"] as? String, !network.isEmpty {
            if let cached = imageCache[network] { return cached }
            fetch(network)
            return UIImage(systemName: "person.crop.circle")
        }
        return nil
    }

    private static func symbolName(for item: [String: Any], selected: Bool) -> String? {
        let name = (selected ? item["selectedSymbol"] as? String : nil) ?? item["symbol"] as? String
        return (name?.isEmpty ?? true) ? nil : name
    }

    private func fetch(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            let avatar = Self.avatar(image)
            DispatchQueue.main.async {
                self?.imageCache[urlString] = avatar
                self?.refreshAppearance()
            }
        }.resume()
    }

    private static func avatar(_ image: UIImage, side: CGFloat = 26) -> UIImage {
        let size = CGSize(width: side, height: side)
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
            let scale = max(side / image.size.width, side / image.size.height)
            let w = image.size.width * scale
            let h = image.size.height * scale
            image.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
        return rendered.withRenderingMode(.alwaysOriginal)
    }

    // MARK: Layout

    private var selectionConstraints: [NSLayoutConstraint] = []
    private weak var selectionAnchor: UIButton?
    private var selectionHorizontal = false

    /// Pill for the glass and the selection highlight. `layer.cornerRadius`
    /// clips the pre-iOS 26 blur; iOS 26 glass follows `cornerConfiguration`.
    private func applyCapsuleShape() {
        let side = horizontal ? container.bounds.height : container.bounds.width
        guard side > 0 else { return }
        effectView.clipsToBounds = true
        effectView.layer.cornerRadius = side / 2
        effectView.layer.cornerCurve = .continuous
        selectionView.layer.cornerRadius = (side - 6) / 2
        selectionView.layer.cornerCurve = .continuous
        if #available(iOS 26.0, *) {
            effectView.cornerConfiguration = .capsule()
            selectionView.cornerConfiguration = .capsule()
        }
    }

    /// UIKit writes the menu's shape after layout, so apply again next turn.
    private func restoreCapsuleShape() {
        applyCapsuleShape()
        DispatchQueue.main.async { [weak self] in self?.applyCapsuleShape() }
    }

    private func layoutChrome(animated: Bool) {
        applyCapsuleShape()

        guard let selected = selectedIndex, selected < buttons.count else {
            selectionView.isHidden = true
            return
        }
        let button = buttons[selected]
        guard selectionAnchor !== button || selectionHorizontal != horizontal else { return }
        selectionHorizontal = horizontal
        let wasVisible = !selectionView.isHidden && selectionAnchor != nil
        selectionAnchor = button

        // The highlight follows the selected button through constraints, so
        // it is right on every layout pass, not only the one it was set in.
        NSLayoutConstraint.deactivate(selectionConstraints)
        selectionView.translatesAutoresizingMaskIntoConstraints = false
        selectionConstraints = [
            selectionView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            selectionView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            horizontal
                ? selectionView.widthAnchor.constraint(equalTo: button.widthAnchor)
                : selectionView.widthAnchor.constraint(equalTo: button.widthAnchor, constant: -6),
            horizontal
                ? selectionView.heightAnchor.constraint(equalTo: button.heightAnchor, constant: -6)
                : selectionView.heightAnchor.constraint(equalTo: button.heightAnchor),
        ]
        NSLayoutConstraint.activate(selectionConstraints)
        selectionView.isHidden = false

        if animated && wasVisible {
            UIView.animate(
                withDuration: 0.35, delay: 0,
                usingSpringWithDamping: 0.8, initialSpringVelocity: 0,
                options: [.beginFromCurrentState],
                animations: { self.effectView.contentView.layoutIfNeeded() })
        }
    }

    @objc private func tapped(_ sender: UIButton) {
        channel.invokeMethod("onItemTapped", arguments: ["index": sender.tag])
    }

    private static func colorFromARGB(_ argb: Int) -> UIColor {
        let a = CGFloat((argb >> 24) & 0xFF) / 255.0
        let r = CGFloat((argb >> 16) & 0xFF) / 255.0
        let g = CGFloat((argb >> 8) & 0xFF) / 255.0
        let b = CGFloat(argb & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}

extension UIImage.SymbolWeight {
    /// Flutter's `FontWeight.value` (100 to 900). Values between the steps
    /// snap to the nearer symbol weight.
    static func fromFontWeight(_ value: Int) -> UIImage.SymbolWeight {
        switch value {
        case ...150: return .ultraLight
        case ...250: return .thin
        case ...350: return .light
        case ...450: return .regular
        case ...550: return .medium
        case ...650: return .semibold
        case ...750: return .bold
        case ...850: return .heavy
        default: return .black
        }
    }
}
