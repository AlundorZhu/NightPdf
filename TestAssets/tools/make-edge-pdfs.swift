// Regenerates TestAssets/edge-cases.pdf (rotated and cropped pages) and
// TestAssets/locked.pdf (password "test") from sample.pdf.
// Run from the repo root: swift TestAssets/tools/make-edge-pdfs.swift

import PDFKit
let src = PDFDocument(url: URL(fileURLWithPath: "TestAssets/sample.pdf"))!
// Rotated + offset-cropbox document
let doc = PDFDocument()
for i in 0..<4 { doc.insert(src.page(at: [0, 5, 5, 1][i])!.copy() as! PDFPage, at: i) }
doc.page(at: 1)!.rotation = 90
let p2 = doc.page(at: 2)!
p2.setBounds(CGRect(x: 150, y: 300, width: 350, height: 400), for: .cropBox)   // zoomed-in crop of the figure page
doc.page(at: 3)!.rotation = 180
doc.write(to: URL(fileURLWithPath: "TestAssets/edge-cases.pdf"))
// Password-protected copy
src.write(to: URL(fileURLWithPath: "TestAssets/locked.pdf"),
          withOptions: [.userPasswordOption: "test", .ownerPasswordOption: "owner"])
print("ok")
