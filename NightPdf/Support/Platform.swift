//
//  Platform.swift
//  NightPdf
//

import SwiftUI

// The few AppKit and UIKit types the shared code names, under one name each.
#if os(macOS)
import AppKit

typealias PlatformColor = NSColor
typealias PlatformImage = NSImage
typealias PlatformView = NSView

extension NSImage {
    /// For cache costs.
    var pixelCount: Int {
        representations.map { $0.pixelsWide * $0.pixelsHigh }.max() ?? 0
    }
}

extension Image {
    init(platformImage: NSImage) {
        self.init(nsImage: platformImage)
    }
}
#else
import UIKit

typealias PlatformColor = UIColor
typealias PlatformImage = UIImage
typealias PlatformView = UIView

extension UIImage {
    /// For cache costs.
    var pixelCount: Int {
        Int(size.width * size.height * scale * scale)
    }
}

extension Image {
    init(platformImage: UIImage) {
        self.init(uiImage: platformImage)
    }
}
#endif
