#if os(macOS)
import AppKit
import Foundation

/// Renders notes into a single paginated PDF via the standard AppKit text-system
/// pattern: lay out an attributed string across as many NSTextContainers as it
/// takes, then draw each container's glyphs into its own PDF page.
public enum PDFExporter {
    private static let pageSize = CGSize(width: 612, height: 792) // US Letter, points
    private static let margin: CGFloat = 54

    public static func renderCombined(_ notes: [Note], documentTitle: String = "Unli Rice — Notes Export") -> Data {
        let contentSize = CGSize(width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)
        let attributed = buildAttributedString(notes: notes, documentTitle: documentTitle)

        let textStorage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        var containers: [NSTextContainer] = []
        let maxPages = 2000
        while containers.count < maxPages {
            let container = NSTextContainer(size: contentSize)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            containers.append(container)

            layoutManager.ensureLayout(for: container)
            let glyphRange = layoutManager.glyphRange(for: container)
            if glyphRange.location + glyphRange.length >= layoutManager.numberOfGlyphs {
                break
            }
        }

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        for container in containers {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            let glyphRange = layoutManager.glyphRange(for: container)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: CGPoint(x: margin, y: margin))
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()

        return data as Data
    }

    private static func buildAttributedString(notes: [Note], documentTitle: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let titleFont = NSFont.boldSystemFont(ofSize: 18)
        let headingFont = NSFont.boldSystemFont(ofSize: 13)
        let bodyFont = NSFont.systemFont(ofSize: 10.5)
        let metaFont = NSFont.systemFont(ofSize: 8.5)
        let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return f
        }()

        result.append(NSAttributedString(string: documentTitle + "\n\n", attributes: [.font: titleFont]))

        for note in notes {
            result.append(NSAttributedString(string: note.title + "\n", attributes: [.font: headingFont]))

            let meta = "Sources: \(note.sources.sorted().joined(separator: ", "))   ·   Updated \(dateFormatter.string(from: note.updatedAt))"
            result.append(NSAttributedString(
                string: meta + "\n\n",
                attributes: [.font: metaFont, .foregroundColor: NSColor.darkGray]
            ))

            let bodyText = note.body.isEmpty ? "(no content)" : note.body
            result.append(NSAttributedString(string: bodyText + "\n\n\n", attributes: [.font: bodyFont]))
        }

        return result
    }
}
#endif
