//
//  CGRect+Finite.swift
//  NightPdf
//

import CoreGraphics

extension CGRect {
    /// False for the null rect and for NaN or infinite coordinates, which
    /// AppKit and UIKit reject as view geometry.
    var isFinite: Bool {
        !isNull && origin.x.isFinite && origin.y.isFinite && size.width.isFinite && size.height.isFinite
    }
}
