//
//  OutlineTests.swift
//  NightPdfTests
//

import PDFKit
import Testing
@testable import NightPdf

/// Each contents entry has its own id, and the id finds its own page; a
/// section mixed up with one of its subsections highlights the wrong one.
@MainActor
struct OutlineTests {
    /// Four blank pages; sections 1 (page 0, with 1.1 on 0 and 1.2 on 1) and
    /// 2 (page 2, with 2.1 on 3), written out as a file would have them.
    private static func makeData() -> Data {
        // Object numbers: 1 catalog, 2 page tree, 3-6 pages, 7 outline root, 8- entries.
        let entries: [(title: String, page: Int, parent: Int, children: [Int])] = [
            ("1", 0, 7, [9, 10]), ("1.1", 0, 8, []), ("1.2", 1, 8, []),
            ("2", 2, 7, [12]), ("2.1", 3, 11, []),
        ]
        var objects = [
            "<< /Type /Catalog /Pages 2 0 R /Outlines 7 0 R >>",
            "<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R 6 0 R] /Count 4 >>",
        ]
        objects += (0..<4).map { _ in "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>" }
        objects.append("<< /Type /Outlines /First 8 0 R /Last 11 0 R /Count 2 >>")
        for (index, entry) in entries.enumerated() {
            let number = 8 + index
            let siblings = entries.indices.filter { entries[$0].parent == entry.parent }.map { 8 + $0 }
            let position = siblings.firstIndex(of: number)!
            var item = "<< /Title (\(entry.title)) /Parent \(entry.parent) 0 R /Dest [\(3 + entry.page) 0 R /XYZ null null null]"
            if position > 0 { item += " /Prev \(siblings[position - 1]) 0 R" }
            if position < siblings.count - 1 { item += " /Next \(siblings[position + 1]) 0 R" }
            if let first = entry.children.first, let last = entry.children.last {
                item += " /First \(first) 0 R /Last \(last) 0 R /Count \(entry.children.count)"
            }
            objects.append(item + " >>")
        }
        var file = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(file.utf8.count)
            file += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = file.utf8.count
        file += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        file += offsets.map { String(format: "%010d 00000 n \n", $0) }.joined()
        file += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(file.utf8)
    }

    @Test func sectionsAndSubsectionsHaveTheirOwnIdsAndPages() async throws {
        let model = ReaderModel(data: Self.makeData(), fileURL: nil)
        while model.outlinePageIndices == nil { try await Task.sleep(for: .milliseconds(10)) }

        func flat(_ nodes: [OutlineNode]) -> [OutlineNode] { nodes.flatMap { [$0] + flat($0.children ?? []) } }
        let nodes = flat(model.outline)
        #expect(nodes.map(\.title) == ["1", "1.1", "1.2", "2", "2.1"])
        #expect(Set(nodes.map(\.id)).count == nodes.count, "ids \(nodes.map(\.id))")
        #expect(nodes.map { model.pageIndex(of: $0) } == [0, 0, 1, 2, 3])
    }
}
