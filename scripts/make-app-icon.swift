// Draws the NightPdf app icon (light, dark and tinted variants) into the asset catalog:
// a white owl by day, a black owl at night, in a soft kawaii style.
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
    var night: Bool            // stars and a moon in the sky
    var outline: CGColor
    var body: CGColor
    var wing: CGColor
    var face: CGColor
    var feathers: CGColor
    var eye: CGColor
    var pupil: CGColor?        // nil: the eye is a single dark dot
    var beak: CGColor
    var blush: CGColor
    var star: CGColor
}

let size = 1024
let variants: [(String, Palette)] = [
    ("AppIcon.png", Palette(
        sky: (rgb(0xBFE3F5), rgb(0xF3FAFD)), night: false, outline: rgb(0x4A3B36),
        body: rgb(0xFBF9F4), wing: rgb(0xE8E2D5), face: rgb(0xFFFFFF), feathers: rgb(0xD6CCBA),
        eye: rgb(0x3A2E2B), pupil: nil, beak: rgb(0xF4A743), blush: rgb(0xF6A3B5, 0.75), star: rgb(0xFFFFFF))),
    ("AppIcon-Dark.png", Palette(
        sky: (rgb(0x223068), rgb(0x0A0E26)), night: true, outline: rgb(0x07070C),
        body: rgb(0x26262E), wing: rgb(0x18181E), face: rgb(0x34343F), feathers: rgb(0x45454F),
        eye: rgb(0xFFD24A), pupil: rgb(0x0E0E12), beak: rgb(0xF4A743), blush: rgb(0xE88AA0, 0.45), star: rgb(0xFFE9A8))),
    ("AppIcon-Tinted.png", Palette(
        sky: (rgb(0x000000), rgb(0x000000)), night: true, outline: rgb(0x000000),
        body: rgb(0x6E6E6E), wing: rgb(0x4E4E4E), face: rgb(0x8E8E8E), feathers: rgb(0xA8A8A8),
        eye: rgb(0xFFFFFF), pupil: rgb(0x1A1A1A), beak: rgb(0xDADADA), blush: rgb(0xFFFFFF, 0.25), star: rgb(0x9A9A9A))),
]

func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, rotation: CGFloat = 0) -> CGPath {
    var t = CGAffineTransform(translationX: cx, y: cy).rotated(by: rotation)
    return CGPath(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), transform: &t)
}

func roundedTriangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    path.move(to: mid)
    path.addArc(tangent1End: b, tangent2End: c, radius: radius)
    path.addArc(tangent1End: c, tangent2End: a, radius: radius)
    path.addArc(tangent1End: a, tangent2End: b, radius: radius)
    path.closeSubpath()
    return path
}

func fill(_ path: CGPath, _ color: CGColor, _ ctx: CGContext) {
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
}

func draw(_ p: Palette, in ctx: CGContext) {
    // Sky.
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [p.sky.bottom, p.sky.top] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])

    if p.night {
        for (x, y, r) in [(170.0, 860.0, 9.0), (250, 700, 6), (120, 560, 7), (880, 610, 8), (930, 420, 6), (150, 330, 5)] {
            fill(ellipse(x, y, r * 2, r * 2), p.star, ctx)
        }
        // Crescent moon, top right: a disc minus an offset disc.
        ctx.saveGState()
        ctx.addPath(ellipse(820, 840, 150, 150))
        ctx.clip()
        ctx.addPath(ellipse(820, 840, 150, 150))
        ctx.addPath(ellipse(862, 872, 130, 130))
        ctx.setFillColor(p.star)
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()
    } else {
        // Soft clouds.
        for (x, y, w) in [(200.0, 830.0, 230.0), (845, 720, 190)] {
            for (dx, dy, s) in [(-0.3, 0.0, 0.55), (0.0, 0.12, 0.7), (0.3, 0.0, 0.55)] {
                fill(ellipse(x + dx * w, y + dy * w, w * s, w * s * 0.8), rgb(0xFFFFFF, 0.85), ctx)
            }
        }
    }

    // Silhouette pieces; the outline is the union of them, stroked wide underneath.
    let earL = roundedTriangle(CGPoint(x: 300, y: 640), CGPoint(x: 285, y: 845), CGPoint(x: 445, y: 720), radius: 26)
    let earR = roundedTriangle(CGPoint(x: 579, y: 720), CGPoint(x: 739, y: 845), CGPoint(x: 724, y: 640), radius: 26)
    let body = ellipse(512, 450, 540, 620)
    let wingL = ellipse(282, 380, 150, 290, rotation: -0.28)
    let wingR = ellipse(742, 380, 150, 290, rotation: 0.28)
    let footL = CGPath(roundedRect: CGRect(x: 420, y: 118, width: 72, height: 48), cornerWidth: 24, cornerHeight: 24, transform: nil)
    let footR = CGPath(roundedRect: CGRect(x: 532, y: 118, width: 72, height: 48), cornerWidth: 24, cornerHeight: 24, transform: nil)
    let silhouette = [earL, earR, wingL, wingR, footL, footR, body]

    ctx.setLineJoin(.round)
    ctx.setLineWidth(28)
    ctx.setStrokeColor(p.outline)
    for piece in silhouette {
        ctx.addPath(piece)
        ctx.strokePath()
    }

    fill(footL, p.beak, ctx)
    fill(footR, p.beak, ctx)
    fill(earL, p.body, ctx)
    fill(earR, p.body, ctx)
    fill(wingL, p.wing, ctx)
    fill(wingR, p.wing, ctx)
    fill(body, p.body, ctx)

    // Wings tucked over the body edge.
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    fill(ellipse(282, 380, 150, 290, rotation: -0.28), p.wing, ctx)
    fill(ellipse(742, 380, 150, 290, rotation: 0.28), p.wing, ctx)
    ctx.restoreGState()

    // Belly feathers: little scallops.
    ctx.setStrokeColor(p.feathers)
    ctx.setLineWidth(12)
    ctx.setLineCap(.round)
    for (x, y) in [(462.0, 345.0), (562, 345), (512, 280), (412, 280), (612, 280), (512, 410)] {
        ctx.move(to: CGPoint(x: x - 30, y: y + 12))
        ctx.addQuadCurve(to: CGPoint(x: x + 30, y: y + 12), control: CGPoint(x: x, y: y - 22))
        ctx.strokePath()
    }

    // Face disc, a soft heart of two circles.
    fill(ellipse(428, 575, 250, 230), p.face, ctx)
    fill(ellipse(596, 575, 250, 230), p.face, ctx)

    // Eyes.
    for x in [428.0, 596.0] {
        if let pupil = p.pupil {
            fill(ellipse(x, 578, 150, 150), p.eye, ctx)
            fill(ellipse(x, 578, 84, 84), pupil, ctx)
        } else {
            fill(ellipse(x, 578, 112, 112), p.eye, ctx)
        }
        fill(ellipse(x + 20, 600, 38, 38), rgb(0xFFFFFF), ctx)
        fill(ellipse(x - 18, 556, 16, 16), rgb(0xFFFFFF, 0.9), ctx)
    }

    // Blush and beak.
    fill(ellipse(352, 488, 86, 44), p.blush, ctx)
    fill(ellipse(672, 488, 86, 44), p.blush, ctx)
    fill(roundedTriangle(CGPoint(x: 476, y: 516), CGPoint(x: 512, y: 452), CGPoint(x: 548, y: 516), radius: 14), p.beak, ctx)
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
