//
//  NightPageTests.swift
//  NightPdfTests
//

import CoreGraphics
import PDFKit
import Testing
@testable import NightPdf

/// Inverted pages must be dark right up to their edges. PDFView fills whole
/// pixels white before the page draws, so a scale that leaves the page height
/// mid-pixel used to leave a white hairline along the top edge.
struct NightPageTests {
    @Test func invertedPageHasNoWhiteEdge() throws {
        let document = try #require(NightDocument(data: blankPage()))
        document.invertsPages = true
        let page = try #require(document.page(at: 0) as? NightPage)
        // 612 x 792 points at 0.3334 -> 264.0 x 204.0 ... height 264.01, mid-pixel.
        let scale: CGFloat = 0.3334
        let width = Int((612 * scale).rounded(.up)), height = Int((792 * scale).rounded(.up))
        let cg = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        cg.setFillColor(gray: 1, alpha: 1)
        cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
        cg.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: cg)

        let image = try #require(cg.makeImage())
        let data = try #require(image.dataProvider?.data) as Data
        let row = image.bytesPerRow
        for y in [0, height / 2, height - 1] {
            for x in [0, width / 2, width - 1] {
                let offset = y * row + x * 4
                let (b, g, r) = (data[offset], data[offset + 1], data[offset + 2])
                #expect(max(r, g, b) < 60, "pixel (\(x), \(y)) is (\(r), \(g), \(b)), not dark")
            }
        }
    }

    private func blankPage() -> Data {
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>",
        ]
        var file = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(file.utf8.count)
            file += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = file.utf8.count
        file += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { file += String(format: "%010d 00000 n \n", offset) }
        file += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(file.utf8)
    }
}
