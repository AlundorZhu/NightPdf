//
//  NightDocument.swift
//  NightPdf
//

import os
import PDFKit

/// A PDF document whose pages can render with inverted colors for dark mode.
final class NightDocument: PDFDocument {
    /// Read from PDFKit's render threads, so it is not main-actor isolated.
    nonisolated(unsafe) var invertsPages = false

    override var pageClass: AnyClass { NightPage.self }
}

/// A page that can draw with inverted colors: its luminance flipped while
/// the hues are kept, so text turns light on a dark page but a red figure
/// stays red.
///
/// In dark mode the page view draws nothing: the night overlay
/// (`PageOverlayProvider`) draws the inverted page over it instead, so
/// PDFKit's white page backing never shows while tiles are rendering.
///
/// Unchecked Sendable: PDFKit already draws pages from its own render threads.
final class NightPage: PDFPage, @unchecked Sendable {
    /// Page background ends up at `1 - inkLevel` gray instead of pure black,
    /// which is softer to read and keeps pages distinct from the black canvas.
    nonisolated static let inkLevel: CGFloat = 0.9

    /// The inverted page's background.
    nonisolated static var nightBackground: CGColor { CGColor(gray: 1 - inkLevel, alpha: 1) }

    nonisolated private var invertsPages: Bool {
        (document as? NightDocument)?.invertsPages == true
    }

    nonisolated override func draw(with box: PDFDisplayBox, to context: CGContext) {
        defer { Signposts.end("Open Document") }
        guard !invertsPages else { return }   // the overlay draws the page
        super.draw(with: box, to: context)
    }

    /// Draws the page as it should look: as printed, or inverted in dark mode.
    nonisolated func drawForDisplay(with box: PDFDisplayBox, to context: CGContext) {
        guard invertsPages else {
            super.draw(with: box, to: context)
            return
        }
        context.saveGState()
        // The clip can extend past the page into the gaps PDFView paints itself.
        let area = context.boundingBoxOfClipPath.intersection(CGRect(origin: .zero, size: displaySize(for: box)))
        context.clip(to: area)
        // The paper, which the inversion below needs under the ink; a layer's
        // context starts out clear.
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(area)
        super.draw(with: box, to: context)
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

    /// Renders through `drawForDisplay(with:to:)` so thumbnails match the
    /// page colors; `PDFPage.thumbnail(of:for:)` skips subclass drawing. `scale` is the
    /// screen's pixels per point. Nil if the bitmap can't be made.
    nonisolated func thumbnail(fitting size: CGSize, scale pixelScale: CGFloat) -> PlatformImage? {
        let pageSize = displaySize(for: .cropBox)
        let scale = min(size.width / pageSize.width, size.height / pageSize.height)
        let imageSize = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)

        return Signposts.signposter.withIntervalSignpost("Render Thumbnail") {
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let cg = CGContext(
                      data: nil, width: Int((imageSize.width * pixelScale).rounded(.up)),
                      height: Int((imageSize.height * pixelScale).rounded(.up)), bitsPerComponent: 8,
                      bytesPerRow: 0, space: space,
                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return nil }
            cg.setFillColor(gray: 1, alpha: 1)
            cg.fill(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            // Bitmap contexts already have PDF's upward y axis; no flip needed.
            cg.scaleBy(x: scale * pixelScale, y: scale * pixelScale)
            drawForDisplay(with: .cropBox, to: cg)
            guard let image = cg.makeImage() else { return nil }
            #if os(macOS)
            return NSImage(cgImage: image, size: imageSize)
            #else
            return UIImage(cgImage: image, scale: pixelScale, orientation: .up)
            #endif
        }
    }

    /// `draw(with:to:)` works in display space: the box moved to the origin,
    /// with width and height swapped for pages rotated a quarter turn.
    nonisolated func displaySize(for box: PDFDisplayBox) -> CGSize {
        let size = bounds(for: box).size
        return rotation % 180 == 0 ? size : CGSize(width: size.height, height: size.width)
    }
}
