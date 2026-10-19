// Generates TestAssets/large.pdf: 1,500 text-heavy pages with a three-level outline,
// for the performance tests. Not committed; scripts/run-ui-tests.sh builds it when missing.
// Run from the repo root: swift TestAssets/tools/make-large-pdf.swift

import CoreGraphics
import CoreText
import Foundation

let pageCount = 1500
let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
let url = URL(fileURLWithPath: "TestAssets/large.pdf")
let words = "night reader page document render outline figure section table chapter result method"
    .split(separator: " ")

var box = pageRect
let context = CGContext(url as CFURL, mediaBox: &box, nil)!
let font = CTFontCreateWithName("Times-Roman" as CFString, 10, nil)
for page in 0..<pageCount {
    context.beginPDFPage(nil)
    var text = "Chapter \(page / 50 + 1), Section \(page / 10 + 1), Page \(page + 1)\n\n"
    for line in 0..<70 {
        text += (0..<14).map { words[(page * 7 + line * 3 + $0) % words.count] }.joined(separator: " ") + "\n"
    }
    let string = NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
    let frame = CTFramesetterCreateFrame(
        CTFramesetterCreateWithAttributedString(string), CFRange(),
        CGPath(rect: pageRect.insetBy(dx: 60, dy: 50), transform: nil), nil)
    CTFrameDraw(frame, context)
    context.endPDFPage()
}

// PDFKit drops outlines added to a document it didn't read them from, so write it here.
func entry(_ title: String, page: Int, children: [[String: Any]] = []) -> [String: Any] {
    var item: [String: Any] = [
        kCGPDFOutlineTitle as String: title,
        kCGPDFOutlineDestination as String: page + 1,   // one-indexed
    ]
    if !children.isEmpty { item[kCGPDFOutlineChildren as String] = children }
    return item
}
let chapters = (0..<(pageCount / 50)).map { chapter in
    entry("Chapter \(chapter + 1)", page: chapter * 50, children: (0..<5).map { section in
        let start = chapter * 50 + section * 10
        return entry("Section \(chapter + 1).\(section + 1)", page: start, children: (0..<5).map { topic in
            entry("Topic \(chapter + 1).\(section + 1).\(topic + 1)", page: start + topic * 2)
        })
    })
}
CGPDFContextSetOutline(context, [kCGPDFOutlineChildren as String: chapters] as CFDictionary)
context.closePDF()
print("wrote \(url.path) (\(pageCount) pages, \(chapters.count * 31) outline entries)")
