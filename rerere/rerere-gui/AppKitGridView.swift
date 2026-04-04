import AppKit
import SwiftUI

// MARK: - Data model for AppKit grid items

struct AppKitGridItem {
    let text: String
    let bgColor: NSColor
}

/// Flatten a TextBit tree into a flat array of grid items, mirroring textBitView logic.
@MainActor
func flattenTextBit(_ bit: TextBit, prompt: Prompt) -> [AppKitGridItem] {
    switch bit {
    case .ing(let ing, item: _):
        let bgColor: NSColor = switch ing.superkind {
            case .meaning: NSColor(meaningBitBackground)
            case .reading, .flashcardBack: NSColor(readingBitBackground)
        }
        return [AppKitGridItem(text: ing.text, bgColor: bgColor)]
    case .character(item: let item):
        return [AppKitGridItem(text: item.character, bgColor: NSColor(defaultBitBackground))]
    case .flashcardFront(item: let item):
        return [AppKitGridItem(text: item.front, bgColor: NSColor(defaultBitBackground))]
    case .unknownItemName(item: let item):
        return [AppKitGridItem(text: item.name, bgColor: NSColor(defaultBitBackground))]
    case .ingsList(superkind: _, children: let children):
        // 100x repeat for testing, matching IngsListView
        var result: [AppKitGridItem] = []
        for _ in 0..<100 {
            for child in children {
                result.append(contentsOf: flattenTextBit(child, prompt: prompt))
            }
        }
        return result
    }
}

// MARK: - Cell view (replicates BasicTextView appearance)

@MainActor private let cellFont = NSFont.systemFont(ofSize: 20)
private let cellInnerPadding: CGFloat = 5
private let cellOuterPadding: CGFloat = 2
private let cellTotalPadding: CGFloat = (cellInnerPadding + cellOuterPadding) * 2
@MainActor private let cellMintColor = NSColor(Color.mint)

class TextBitCellView: NSView {
    private let label: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.font = cellFont
        tf.textColor = .white
        tf.backgroundColor = .clear
        tf.drawsBackground = false
        tf.isBezeled = false
        tf.isEditable = false
        tf.isSelectable = true
        tf.lineBreakMode = .byWordWrapping
        tf.maximumNumberOfLines = 0
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    private var bgColor: NSColor = .clear
    private var isHovered: Bool = false {
        didSet {
            guard oldValue != isHovered else { return }
            needsDisplay = true
            CATransaction.begin()
            CATransaction.setAnimationDuration(isHovered ? 0.005 : 0.12)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeIn))
            layer?.transform = isHovered
                ? CATransform3DMakeScale(1.1, 1.1, 1.0)
                : CATransform3DIdentity
            CATransaction.commit()
        }
    }
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.masksToBounds = false

        // Drop shadow on the cell (matches .shadow(radius: 2, x: 2, y: 2))
        layer?.shadowRadius = 2
        layer?.shadowOffset = CGSize(width: 2, height: -2)
        layer?.shadowOpacity = 0.33
        layer?.shadowColor = NSColor.black.cgColor

        // Text shadow (matches .foregroundStyle(.white.shadow(.drop(radius: 0, x: 2, y: 2))))
        let textShadow = NSShadow()
        textShadow.shadowOffset = NSSize(width: 2, height: -2)
        textShadow.shadowBlurRadius = 0
        textShadow.shadowColor = NSColor.black.withAlphaComponent(0.33)
        label.shadow = textShadow

        addSubview(label)
        let inset = cellInnerPadding + cellOuterPadding
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
        ])
    }

    func configure(text: String, bgColor: NSColor) {
        label.stringValue = text
        self.bgColor = bgColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let bgRect = bounds.insetBy(dx: cellOuterPadding, dy: cellOuterPadding)
        let path = NSBezierPath(roundedRect: bgRect, xRadius: 5, yRadius: 5)

        let fillColor = isHovered
            ? (bgColor.blended(withFraction: 0.2, of: .white) ?? bgColor)
            : bgColor
        fillColor.setFill()
        path.fill()

        cellMintColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        layer?.shadowPath = CGPath(
            roundedRect: bgRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = hoverTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }
}

// MARK: - Collection view item

private let textBitCellID = NSUserInterfaceItemIdentifier("TextBitCell")

class TextBitCollectionViewItem: NSCollectionViewItem {
    override func loadView() {
        self.view = TextBitCellView(frame: .zero)
    }

    func configure(text: String, bgColor: NSColor) {
        (view as! TextBitCellView).configure(text: text, bgColor: bgColor)
    }
}

// MARK: - NSViewRepresentable

struct AppKitGridViewRepresentable: NSViewRepresentable {
    let items: [AppKitGridItem]

    class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
        var items: [AppKitGridItem] = []

        func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

        func collectionView(
            _ collectionView: NSCollectionView, numberOfItemsInSection section: Int
        ) -> Int {
            items.count
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            itemForRepresentedObjectAt indexPath: IndexPath
        ) -> NSCollectionViewItem {
            let item = collectionView.makeItem(
                withIdentifier: textBitCellID, for: indexPath) as! TextBitCollectionViewItem
            let data = items[indexPath.item]
            item.configure(text: data.text, bgColor: data.bgColor)
            return item
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            layout collectionViewLayout: NSCollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> NSSize {
            let data = items[indexPath.item]
            let attrs: [NSAttributedString.Key: Any] = [.font: cellFont]

            // Single-line size
            let textSize = (data.text as NSString).size(withAttributes: attrs)
            let singleLineWidth = ceil(textSize.width) + cellTotalPadding
            let singleLineHeight = ceil(textSize.height) + cellTotalPadding

            let availableWidth = collectionView.bounds.width
            if availableWidth <= 0 || singleLineWidth <= availableWidth {
                return NSSize(width: singleLineWidth, height: singleLineHeight)
            }

            // Text needs to wrap within the available width
            let maxTextWidth = max(availableWidth - cellTotalPadding, 1)
            let boundingRect = (data.text as NSString).boundingRect(
                with: NSSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: attrs
            )
            return NSSize(
                width: availableWidth,
                height: ceil(boundingRect.height) + cellTotalPadding)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let collectionView = NSCollectionView()
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = false

        let flowLayout = NSCollectionViewFlowLayout()
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.minimumLineSpacing = 0
        flowLayout.scrollDirection = .vertical
        collectionView.collectionViewLayout = flowLayout

        collectionView.register(
            TextBitCollectionViewItem.self, forItemWithIdentifier: textBitCellID)

        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator

        scrollView.documentView = collectionView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.items = items
        if let collectionView = scrollView.documentView as? NSCollectionView {
            collectionView.reloadData()
        }
    }
}
