//
//  Digitizer.swift
//  Touch Up
//
//  Created by Sebastian Hueber on 22.05.26.
//

import Foundation
import CoreGraphics

/// Per-digitizer settings, keyed by `HIDLocationID` and persisted to `UserDefaults`.
///
/// Only the screen identity (`screenID` + `screenUUID`) and `additionalRotation` are stored.
/// The actually resolved `TUCScreen` is *not* kept here: the screen list is rebuilt from
/// scratch on every display reconfiguration, so any held reference would go stale. The screen
/// is therefore resolved lazily from this identity (see `TouchUp.resolvedMapping(forLocationID:)`).
struct DigitizerConfig: Codable, Hashable {
    /// `CGDirectDisplayID` — effectively the index in the screen arrangement. Weaker match.
    var screenID: UInt?
    /// Stable per physical panel across launches/rearrangements. Stronger match.
    var screenUUID: String?
    var additionalRotation: CGFloat = 0
    /// Affine correction for a digitizer that doesn't line up with its panel. `nil` = none.
    /// Optional so configs saved by older versions still decode.
    var calibration: DigitizerCalibration?
}


/// An affine map from the raw digitizer point (normalised, digitizer orientation) to the point
/// a perfectly aligned digitizer would report:  x' = a·x + c·y + tx,  y' = b·x + d·y + ty
struct DigitizerCalibration: Codable, Hashable {
    var a: Double = 1, b: Double = 0, c: Double = 0, d: Double = 1, tx: Double = 0, ty: Double = 0

    init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        (self.a, self.b, self.c, self.d, self.tx, self.ty) = (a, b, c, d, tx, ty)
    }

    var transform: CGAffineTransform {
        CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }

    /// Least-squares affine fit mapping `raw[i]` onto `target[i]`. Needs at least three
    /// non-collinear pairs; more points average out finger-placement error.
    /// Returns `nil` if the points are degenerate or the result is implausible
    /// (e.g. a target was tapped in the wrong place).
    static func fit(raw: [CGPoint], target: [CGPoint]) -> DigitizerCalibration? {
        guard raw.count == target.count, raw.count >= 3 else { return nil }

        // Normal equations  MᵀM·p = Mᵀu  with rows [x, y, 1], solved once per output axis.
        var m = [[Double]](repeating: [0, 0, 0], count: 3)
        var bu = [0.0, 0.0, 0.0], bv = [0.0, 0.0, 0.0]
        for (r, t) in zip(raw, target) {
            let row = [Double(r.x), Double(r.y), 1.0]
            for i in 0..<3 {
                for j in 0..<3 { m[i][j] += row[i] * row[j] }
                bu[i] += row[i] * Double(t.x)
                bv[i] += row[i] * Double(t.y)
            }
        }

        guard let pu = solve3x3(m, bu), let pv = solve3x3(m, bv) else { return nil }
        let result = DigitizerCalibration(a: pu[0], b: pv[0], c: pu[1], d: pv[1], tx: pu[2], ty: pv[2])

        // A real misalignment is a small correction. Reject anything that scales the
        // surface by more than 2x or collapses it — that means a sample was bad.
        let det = abs(result.a * result.d - result.b * result.c)
        guard det.isFinite, det > 0.25, det < 4 else { return nil }
        return result
    }

    private static func solve3x3(_ m: [[Double]], _ b: [Double]) -> [Double]? {
        func det(_ k: [[Double]]) -> Double {
            k[0][0] * (k[1][1] * k[2][2] - k[1][2] * k[2][1])
          - k[0][1] * (k[1][0] * k[2][2] - k[1][2] * k[2][0])
          + k[0][2] * (k[1][0] * k[2][1] - k[1][1] * k[2][0])
        }
        let d = det(m)
        guard abs(d) > 1e-12 else { return nil }
        // Cramer's rule — plenty for a well-conditioned 3x3.
        return (0..<3).map { col in
            var k = m
            for row in 0..<3 { k[row][col] = b[row] }
            return det(k) / d
        }
    }
}

/// How confidently a digitizer's stored screen identity could be resolved against the
/// currently connected screens. Transient (computed on every resolution), never persisted.
/// Intended purely as a UI hint to flag potentially wrong mappings.
enum ScreenMatch {
    case exact       // UUID hit — safe
    case idFallback  // only the display ID matched; UUID gone/changed (e.g. after a rearrange)
    case implicit    // no stored match; fell back to the most recently added screen
    case unmapped    // no screen could be resolved at all
}

struct Digitizer: Codable, Hashable, Identifiable {

    let locationID: HIDLocationID
    let name: String?
    let vendorID: UInt16?
    let productID: UInt16?
    let bcdDevice: UInt16?
    let serialNumber: String?

    init(locationID: HIDLocationID) {
        let properties = locationID.properties
        self.locationID = locationID
        self.name = properties?.name
        self.vendorID = properties?.vendorID
        self.productID = properties?.productID
        self.bcdDevice = properties?.bcdDevice
        self.serialNumber = properties?.serialNumber
    }
    
    var deviceName: String {
        self.name ?? "Touch Digitizer"
    }
    
    var locationIDString: String {
        "0x\(String(format: "%08x", locationID))"
    }

    var isUniquelyIdentifiable: Bool {
        serialNumber != nil
    }
    
    var id: HIDLocationID {
        locationID
    }
}
