// Draws the NightPdf app icon (light, dark and tinted variants) into the asset catalog:
// a white owl by day, a black owl at night, in a clean flat style.
// Run from the repo root: swift scripts/make-app-icon.swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

struct Palette {
    var sky: (top: CGColor, bottom: CGColor)
    var moon: CGColor?
    var body: CGColor
    var wing: CGColor
    var face: CGColor
    var eye: CGColor
    var pupil: CGColor
    var beak: CGColor
    var branch: CGColor
}

let size = 1024
let variants: [(String, Palette)] = [
    ("AppIcon.png", Palette(
        sky: (rgb(0xD3E2EC), rgb(0xEDF3F7)), moon: nil,
        body: rgb(0xFFFFFF), wing: rgb(0xE3E8ED), face: rgb(0xF2F4F6),
        eye: rgb(0xF2F4F6), pupil: rgb(0x2A2E35), beak: rgb(0xE0A23A), branch: rgb(0x8A7767))),
    ("AppIcon-Dark.png", Palette(
        sky: (rgb(0x1C2647), rgb(0x0B1024)), moon: rgb(0xE9E4D4),
        body: rgb(0x16171C), wing: rgb(0x0C0D10), face: rgb(0x22242B),
        eye: rgb(0xF0B43C), pupil: rgb(0x0C0D10), beak: rgb(0xE0A23A), branch: rgb(0x3A4366))),
    ("AppIcon-Tinted.png", Palette(
        sky: (rgb(0x000000), rgb(0x000000)), moon: rgb(0x8A8A8A),
        body: rgb(0x9A9A9A), wing: rgb(0x6E6E6E), face: rgb(0xB8B8B8),
        eye: rgb(0xFFFFFF), pupil: rgb(0x1A1A1A), beak: rgb(0xD0D0D0), branch: rgb(0x555555))),
]

func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h), transform: nil)
}

func fill(_ path: CGPath, _ color: CGColor, _ ctx: CGContext) {
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
}

/// The owl's silhouette: straight sides, a round base, and two ear points.
func owlBody() -> CGPath {
    let left: CGFloat = 300, right: CGFloat = 724, shoulder: CGFloat = 470, top: CGFloat = 742
    let path = CGMutablePath()
    path.move(to: CGPoint(x: left, y: shoulder))
    path.addCurve(to: CGPoint(x: 512, y: 190), control1: CGPoint(x: left, y: 300), control2: CGPoint(x: 390, y: 190))
    path.addCurve(to: CGPoint(x: right, y: shoulder), control1: CGPoint(x: 634, y: 190), control2: CGPoint(x: right, y: 300))
    // Ears: up the side to a softened tip, then down and inward to the brow.
    path.addArc(tangent1End: CGPoint(x: right, y: 860), tangent2End: CGPoint(x: right - 110, y: top), radius: 22)
    path.addLine(to: CGPoint(x: right - 110, y: top))
    path.addQuadCurve(to: CGPoint(x: left + 110, y: top), control: CGPoint(x: 512, y: top - 34))
    path.addArc(tangent1End: CGPoint(x: left, y: 860), tangent2End: CGPoint(x: left, y: shoulder), radius: 22)
    path.closeSubpath()
    return path
}

func draw(_ p: Palette, in ctx: CGContext) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [p.sky.bottom, p.sky.top] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])

    if let moon = p.moon {
        // Thin crescent: a disc with an offset disc erased from it.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        fill(ellipse(806, 836, 120, 120), moon, ctx)
        ctx.setBlendMode(.destinationOut)
        fill(ellipse(838, 860, 112, 112), moon, ctx)
        ctx.setBlendMode(.normal)
        ctx.endTransparencyLayer()
    }

    // Branch.
    fill(CGPath(roundedRect: CGRect(x: 170, y: 168, width: 684, height: 34), cornerWidth: 17, cornerHeight: 17, transform: nil),
         p.branch, ctx)

    let body = owlBody()
    fill(body, p.body, ctx)

    // Wings: the lower sides of the body, cut by a curve.
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    for side: CGFloat in [-1, 1] {
        let wing = CGMutablePath()
        let edge = 512 + side * 230
        wing.move(to: CGPoint(x: edge, y: 520))
        wing.addQuadCurve(to: CGPoint(x: 512 + side * 60, y: 170), control: CGPoint(x: 512 + side * 120, y: 470))
        wing.addLine(to: CGPoint(x: edge, y: 170))
        wing.closeSubpath()
        fill(wing, p.wing, ctx)
    }
    ctx.restoreGState()

    // Face: two plain discs, round pupils, a small beak.
    for side: CGFloat in [-1, 1] {
        let x = 512 + side * 100
        fill(ellipse(x, 600, 190, 190), p.face, ctx)
        fill(ellipse(x, 600, 150, 150), p.eye, ctx)
        fill(ellipse(x, 600, 64, 64), p.pupil, ctx)
    }
    let beak = CGMutablePath()
    beak.move(to: CGPoint(x: 486, y: 528))
    beak.addLine(to: CGPoint(x: 538, y: 528))
    beak.addLine(to: CGPoint(x: 512, y: 474))
    beak.closeSubpath()
    fill(beak, p.beak, ctx)
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
