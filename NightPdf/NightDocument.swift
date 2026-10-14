//
//  NightDocument.swift
//  NightPdf
//

import PDFKit

/// A PDF document whose pages can render with inverted colors for dark mode.
final class NightDocument: PDFDocument {
    /// Read from PDFKit's render threads, so it is not main-actor isolated.
    nonisolated(unsafe) var invertsPages = false

    override var pageClass: AnyClass { NightPage.self }
}

/// Draws the page normally, then inverts its luminance while keeping hues,
/// so text turns light on a dark page but a red figure stays red.
final class NightPage: PDFPage {
    /// Page background ends up at `1 - inkLevel` gray instead of pure black,
    /// which is softer to read and keeps pages distinct from the black canvas.
    nonisolated private static let inkLevel: CGFloat = 0.9

    nonisolated override func draw(with box: PDFDisplayBox, to context: CGContext) {
        super.draw(with: box, to: context)
        guard (document as? NightDocument)?.invertsPages == true else { return }

        context.saveGState()
        // The clip can extend past the page into the gaps PDFView paints itself.
        let area = context.boundingBoxOfClipPath.intersection(CGRect(origin: .zero, size: displaySize(for: box)))
        context.clip(to: area)
        context.setBlendMode(.difference)
        context.setFillColor(gray: Self.inkLevel, alpha: 1)
        context.fill(area)

        // Re-apply the original hues on top of the inverted luminance.
        context.setBlendMode(.hue)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        super.draw(with: box, to: context)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// `draw(with:to:)` works in display space: the box moved to the origin,
    /// with width and height swapped for pages rotated a quarter turn.
    nonisolated func displaySize(for box: PDFDisplayBox) -> CGSize {
        let size = bounds(for: box).size
        return rotation % 180 == 0 ? size : CGSize(width: size.height, height: size.width)
    }
}
