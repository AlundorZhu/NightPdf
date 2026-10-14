// Draws the NightPdf app icon (light, dark and tinted variants) into the asset catalog.
// Run from the repo root: swift scripts/make-app-icon.swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Palette {
    var background: (CGColor, CGColor)?   // top, bottom; nil = transparent
    var page: CGColor
    var fold: CGColor
    var lines: CGColor
    var moon: CGColor
    var moonOutline: CGColor?
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let size = 1024
let variants: [(String, Palette)] = [
    ("AppIcon.png", Palette(background: (rgb(0x2B3A78), rgb(0x0D1230)), page: rgb(0xFFFFFF), fold: rgb(0xC9CFE6),
                            lines: rgb(0xA9B1CC), moon: rgb(0xFFC94A), moonOutline: rgb(0x121839))),
    ("AppIcon-Dark.png", Palette(background: (rgb(0x23252E), rgb(0x050507)), page: rgb(0x2E3038), fold: rgb(0x4A4D58),
                                 lines: rgb(0x9A9EAD), moon: rgb(0xFFC94A), moonOutline: rgb(0x0A0A0D))),
    ("AppIcon-Tinted.png", Palette(background: (rgb(0x000000), rgb(0x000000)), page: rgb(0x8C8C8C), fold: rgb(0x5C5C5C),
                                   lines: rgb(0x2E2E2E), moon: rgb(0xFFFFFF), moonOutline: rgb(0x000000))),
]

func draw(_ p: Palette, in ctx: CGContext) {
    let full = CGRect(x: 0, y: 0, width: size, height: size)
    if let (top, bottom) = p.background {
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [bottom, top] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])
    } else {
        ctx.clear(full)
    }

    // Page with a folded top-right corner.
    let page = CGRect(x: 232, y: 170, width: 520, height: 680)
    let r: CGFloat = 44, fold: CGFloat = 150
    let path = CGMutablePath()
    path.move(to: CGPoint(x: page.minX + r, y: page.minY))
    path.addLine(to: CGPoint(x: page.maxX - r, y: page.minY))
    path.addArc(tangent1End: CGPoint(x: page.maxX, y: page.minY), tangent2End: CGPoint(x: page.maxX, y: page.minY + r), radius: r)
    path.addLine(to: CGPoint(x: page.maxX, y: page.maxY - fold))
    path.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY))
    path.addLine(to: CGPoint(x: page.minX + r, y: page.maxY))
    path.addArc(tangent1End: CGPoint(x: page.minX, y: page.maxY), tangent2End: CGPoint(x: page.minX, y: page.maxY - r), radius: r)
    path.addLine(to: CGPoint(x: page.minX, y: page.minY + r))
    path.addArc(tangent1End: CGPoint(x: page.minX, y: page.minY), tangent2End: CGPoint(x: page.minX + r, y: page.minY), radius: r)
    path.closeSubpath()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 40, color: rgb(0x000000, 0.35))
    ctx.addPath(path)
    ctx.setFillColor(p.page)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    let flap = CGMutablePath()
    flap.move(to: CGPoint(x: page.maxX - fold, y: page.maxY))
    flap.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY - fold + 24))
    flap.addQuadCurve(to: CGPoint(x: page.maxX - fold + 24, y: page.maxY - fold),
                      control: CGPoint(x: page.maxX - fold, y: page.maxY - fold))
    flap.addLine(to: CGPoint(x: page.maxX, y: page.maxY - fold))
    flap.closeSubpath()
    ctx.addPath(flap)
    ctx.setFillColor(p.fold)
    ctx.fillPath()

    // Text lines.
    ctx.setFillColor(p.lines)
    let widths: [CGFloat] = [250, 380, 380, 330, 380, 210]
    for (i, w) in widths.enumerated() {
        let y = page.maxY - 120 - CGFloat(i) * 72 - (i == 0 ? 0 : 40)
        ctx.addPath(CGPath(roundedRect: CGRect(x: page.minX + 70, y: y, width: w, height: 30),
                           cornerWidth: 15, cornerHeight: 15, transform: nil))
        ctx.fillPath()
    }

    // Crescent moon over the bottom-right corner, with an outline in the
    // background color so it separates from the page.
    let outer = CGRect(x: page.maxX - 190, y: page.minY - 30, width: 300, height: 300)
    let inner = outer.offsetBy(dx: 95, dy: 75).insetBy(dx: 10, dy: 10)
    if let outline = p.moonOutline {
        crescent(outer: outer.insetBy(dx: -22, dy: -22), inner: inner.insetBy(dx: 22, dy: 22), color: outline, in: ctx)
    }
    crescent(outer: outer, inner: inner, color: p.moon, in: ctx)
}

/// Fills `outer` minus `inner`.
func crescent(outer: CGRect, inner: CGRect, color: CGColor, in ctx: CGContext) {
    ctx.saveGState()
    ctx.addEllipse(in: outer)
    ctx.clip()
    ctx.addRect(outer)
    ctx.addEllipse(in: inner)
    ctx.setFillColor(color)
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()
}

let directory = URL(fileURLWithPath: "NightPdf/Assets.xcassets/AppIcon.appiconset")
for (name, palette) in variants {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    draw(palette, in: ctx)
    let dest = CGImageDestinationCreateWithURL(directory.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}
print("wrote \(variants.count) icons")
