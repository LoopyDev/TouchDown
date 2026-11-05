//
//  CalibrationView.swift
//  Touch Up
//
//  Five-point touch calibration: the user touches a sequence of crosshairs, we fit an
//  affine correction from where the digitizer *reported* each touch to where it *should*
//  have been, then let them try it out before saving.
//

import Cocoa
import SwiftUI
import TouchUpCore


// MARK: - Window

class CalibrationOverlay: NSWindow {

    static func overlay(model: TouchUp,
                        locationID: HIDLocationID,
                        finish: @escaping (DigitizerCalibration?) -> Void) -> CalibrationOverlay {
        let view = CalibrationView(model: model, locationID: locationID, finish: finish)
        let vc = NSHostingController(rootView: view)

        let window = CalibrationOverlay(contentRect: .zero,
                                        styleMask: [.resizable, .fullSizeContentView],
                                        backing: .buffered,
                                        defer: true,
                                        screen: nil)
        window.title = "Calibrate Touchscreen"
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false

        let windowController = NSWindowController(window: window)
        windowController.contentViewController = vc
        return window
    }

    func makeVisible(onScreen targetScreen: TUCScreen) {
        self.setIsVisible(true)
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        guard let controller = self.contentViewController,
              let screen = targetScreen.systemScreen() else { return }

        self.level = .screenSaver
        let presentationOptions: NSApplication.PresentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching]
        let options: [NSView.FullScreenModeOptionKey : NSNumber] = [
            .fullScreenModeApplicationPresentationOptions : NSNumber(value: presentationOptions.rawValue),
            .fullScreenModeWindowLevel : NSNumber(value: kCGPopUpMenuWindowLevel),
            .fullScreenModeAllScreens : NSNumber(booleanLiteral: false)
        ]
        self.setIsVisible(false)
        controller.view.enterFullScreenMode(screen, withOptions: options)
    }

    override func close() {
        if let controller = self.contentViewController, controller.view.isInFullScreenMode {
            self.level = .normal
            self.setIsVisible(true)
            controller.view.exitFullScreenMode(options: nil)
        }
        super.close()
    }
}


// MARK: - View

struct CalibrationView: View {

    @ObservedObject var model: TouchUp
    let locationID: HIDLocationID

    /// Called with the calibration to save, or `nil` if the user cancelled.
    let finish: (DigitizerCalibration?) -> Void

    /// Targets in relative screen coordinates. Corners are inset so a finger can reach the
    /// crosshair centre comfortably, and the centre point anchors the fit against skew.
    static let targets: [CGPoint] = [
        CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1),
        CGPoint(x: 0.9, y: 0.9), CGPoint(x: 0.1, y: 0.9),
        CGPoint(x: 0.5, y: 0.5)
    ]

    static let targetNames = ["top left", "top right", "bottom right", "bottom left", "centre"]

    /// How long the finger must stay within `holdToleranceMM` before a point is captured.
    static let holdDuration: TimeInterval = 0.5
    static let holdToleranceMM: CGFloat = 1.5
    /// A point that still misses its target by more than this after the fit was probably
    /// touched off-target, and would skew the correction for the whole screen.
    static let outlierThresholdMM: Double = 4

    private enum Stage { case collecting, review, failed }

    private enum Failure {
        case degenerate
        case outlier(index: Int, mm: Double)
    }

    @State private var stage: Stage = .collecting
    @State private var failure: Failure = .degenerate
    @State private var rawSamples: [CGPoint] = []          // one per completed target
    @State private var trackedTouch: UUID?
    @State private var stillSegment: [CGPoint] = []        // raw positions since the finger last settled
    @State private var stillSince: Date?
    @State private var holdProgress: Double = 0
    @State private var capturedCurrentTouch = false        // point taken; waiting for the finger to lift
    @State private var showHoldHint = false
    @State private var candidate: DigitizerCalibration?
    @State private var buttonFrames: [String: CGRect] = [:]

    /// Drives the hold progress. Digitizers often stop reporting while a finger is perfectly
    /// still, so the hold has to be timed independently of incoming touch updates.
    private let ticker = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()

    private var touchManager: TUCTouchInputManager { model.touchManager }

    private var screen: TUCScreen? { model.touchscreen(forLocationID: locationID) }

    private var pixelsPerMM: CGFloat { screen?.pixelsPerMM() ?? 4 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(white: 0.08)

                switch stage {
                case .collecting: collectingLayer(size: geo.size)
                case .review:     reviewLayer(size: geo.size)
                case .failed:     failedLayer
                }
            }
            .coordinateSpace(name: "calibration")
            .onPreferenceChange(ButtonFrameKey.self) { buttonFrames = $0 }
            .onReceive(model.$touches) { touches in
                handle(touches: touches, size: geo.size)
            }
            .onReceive(ticker) { _ in tick() }
        }
        .ignoresSafeArea()
        .foregroundColor(.white)
    }


    // MARK: Stages

    @ViewBuilder
    private func collectingLayer(size: CGSize) -> some View {
        let index = rawSamples.count

        ForEach(Array(Self.targets.enumerated()), id: \.offset) { i, target in
            Crosshair(state: i < index ? .done : (i == index ? .active : .pending),
                      size: 12 * pixelsPerMM,
                      progress: i == index ? holdProgress : 0)
                .position(x: target.x * size.width, y: target.y * size.height)
        }

        // Where the digitizer currently thinks the finger is, without any calibration —
        // so you can see the error you're correcting.
        ForEach(liveTouches, id: \.uuid) { touch in
            Circle()
                .stroke(Color.orange, lineWidth: 2)
                .frame(width: 6 * pixelsPerMM, height: 6 * pixelsPerMM)
                .position(position(of: touch.rawLocation, calibration: .identity, in: size))
        }

        VStack(spacing: 12) {
            Text("Touch the centre of each crosshair and hold still until the ring fills")
                .font(.system(size: 28, weight: .medium, design: .rounded))
            Text("\(min(index + 1, Self.targets.count)) of \(Self.targets.count)")
                .font(.system(size: 20, design: .rounded))
                .foregroundColor(.gray)
            Text("Lifted too early — keep your finger still a moment longer")
                .font(.system(size: 18, design: .rounded))
                .foregroundColor(.orange)
                .opacity(showHoldHint ? 1 : 0)
            Button("Cancel (Esc)") { finish(nil) }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.borderless)
                .foregroundColor(.gray)
                .padding(.top, 8)
        }
        .position(x: size.width / 2, y: size.height * 0.32)
    }

    @ViewBuilder
    private func reviewLayer(size: CGSize) -> some View {
        let calibration = candidate?.transform ?? .identity

        ForEach(Array(Self.targets.enumerated()), id: \.offset) { i, target in
            Crosshair(state: .done, size: 12 * pixelsPerMM, progress: 0)
                .position(x: target.x * size.width, y: target.y * size.height)
            // where each sample now lands
            if i < rawSamples.count {
                Circle()
                    .fill(Color.green)
                    .frame(width: 2 * pixelsPerMM, height: 2 * pixelsPerMM)
                    .position(position(of: rawSamples[i], calibration: calibration, in: size))
            }
        }

        ForEach(liveTouches, id: \.uuid) { touch in
            Circle()
                .fill(Color.green.opacity(0.5))
                .frame(width: 10 * pixelsPerMM, height: 10 * pixelsPerMM)
                .position(position(of: touch.rawLocation, calibration: calibration, in: size))
        }

        VStack(spacing: 16) {
            Text("Try it out — touches now use the new calibration")
                .font(.system(size: 28, weight: .medium, design: .rounded))
            Text(errorSummary)
                .font(.system(size: 18, design: .rounded))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            HStack(spacing: 24) {
                touchButton("save", "Save", prominent: true) { finish(candidate) }
                    .keyboardShortcut(.defaultAction)
                touchButton("redo", "Start Over") { restart() }
                touchButton("cancel", "Cancel") { finish(nil) }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 8)
        }
        .position(x: size.width / 2, y: size.height * 0.32)
    }

    private var failedLayer: some View {
        VStack(spacing: 16) {
            Text("Those points don't add up")
                .font(.system(size: 28, weight: .medium, design: .rounded))
            Text(failureDetail)
                .font(.system(size: 18, design: .rounded))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            HStack(spacing: 24) {
                touchButton("redo", "Start Over", prominent: true) { restart() }
                    .keyboardShortcut(.defaultAction)
                // A screen with genuinely non-linear error can't get under the threshold,
                // so don't trap the user in a loop.
                if candidate != nil {
                    touchButton("save", "Use Anyway") { finish(candidate) }
                }
                touchButton("cancel", "Cancel") { finish(nil) }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private var failureDetail: String {
        switch failure {
        case .degenerate:
            return "One of the touches was probably off-target. Let's go again."
        case let .outlier(index, mm):
            return String(format: "The %@ point is still %.1f mm off after calibrating — it was probably touched off-centre.\nStart over for an accurate result.",
                          Self.targetNames[index], mm)
        }
    }


    // MARK: Touch handling

    private var liveTouches: [TUCTouch] {
        model.touches.filter { $0.locationID == locationID && $0.isActive() }
    }

    /// Follows one finger at a time. While collecting, a point is captured once the finger has
    /// held still for `holdDuration` (see `tick`) — never on lift, so the smear as the finger
    /// leaves the glass can't leak in. In review, a lift is treated as a tap on a button.
    private func handle(touches: [TUCTouch], size: CGSize) {
        let mine = touches.filter { $0.locationID == locationID }

        if let id = trackedTouch {
            if let touch = mine.first(where: { $0.uuid == id }), touch.isActive() {
                addSample(touch.rawLocation)
            } else {
                let segment = stillSegment
                let captured = capturedCurrentTouch
                resetTracking()
                touchLifted(segment: segment, captured: captured, size: size)
            }
        } else if let touch = mine.first(where: { $0.isActive() }) {
            trackedTouch = touch.uuid
            capturedCurrentTouch = false
            showHoldHint = false
            stillSegment = [touch.rawLocation]
            stillSince = Date()
        }
    }

    /// Extends the current still segment, or restarts it (and the hold timer) if the finger
    /// has drifted too far from where it settled.
    private func addSample(_ raw: CGPoint) {
        guard !capturedCurrentTouch else { return }
        if let anchor = stillSegment.first, distanceMM(anchor, raw) > Self.holdToleranceMM {
            stillSegment = [raw]
            stillSince = Date()
        } else {
            stillSegment.append(raw)
        }
    }

    private func tick() {
        guard stage == .collecting, trackedTouch != nil, !capturedCurrentTouch,
              let since = stillSince else { return }

        holdProgress = min(Date().timeIntervalSince(since) / Self.holdDuration, 1)
        guard holdProgress >= 1 else { return }

        capturedCurrentTouch = true
        holdProgress = 0   // the ring now belongs to the next target
        rawSamples.append(Self.median(of: stillSegment))
        if rawSamples.count == Self.targets.count {
            computeCandidate()
        }
    }

    private func resetTracking() {
        trackedTouch = nil
        stillSegment = []
        stillSince = nil
        holdProgress = 0
    }

    private func touchLifted(segment: [CGPoint], captured: Bool, size: CGSize) {
        // The lift that ends a captured hold is not a button tap, even if the last capture
        // just switched us into review.
        guard !captured, !segment.isEmpty else { return }

        switch stage {
        case .collecting:
            showHoldHint = true

        case .review, .failed:
            // Mouse events are off during calibration, so make the buttons touchable directly.
            let calibration = stage == .review ? (candidate?.transform ?? .identity) : .identity
            let p = position(of: Self.median(of: segment), calibration: calibration, in: size)
            if buttonFrames["save"]?.contains(p) == true, candidate != nil {
                finish(candidate)
            } else if buttonFrames["redo"]?.contains(p) == true {
                restart()
            } else if buttonFrames["cancel"]?.contains(p) == true {
                finish(nil)
            }
        }
    }

    /// Per-axis median, robust against the odd jittery report.
    static func median(of samples: [CGPoint]) -> CGPoint {
        func median(_ v: [CGFloat]) -> CGFloat {
            let s = v.sorted()
            return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
        }
        return CGPoint(x: median(samples.map(\.x)), y: median(samples.map(\.y)))
    }

    /// Physical distance between two raw digitizer points, ignoring any calibration.
    private func distanceMM(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let physical = screen?.nativePhysicalSize ?? .zero
        guard physical.width > 0, physical.height > 0 else {
            // Unknown panel size: assume roughly 500 mm across, about a 24" panel.
            return hypot(a.x - b.x, a.y - b.y) * 500
        }
        let pa = touchManager.relativeScreenPoint(forDigitizerPoint: a, calibration: .identity, locationID: locationID)
        let pb = touchManager.relativeScreenPoint(forDigitizerPoint: b, calibration: .identity, locationID: locationID)
        return hypot((pa.x - pb.x) * physical.width, (pa.y - pb.y) * physical.height)
    }


    // MARK: Fit

    private func computeCandidate() {
        // Express each on-screen target in raw digitizer space (undoing rotation/letterbox),
        // so the correction lives in the digitizer's own frame.
        let expected = Self.targets.map {
            touchManager.digitizerPoint(forRelativeScreenPoint: $0, locationID: locationID)
        }
        guard let fit = DigitizerCalibration.fit(raw: rawSamples, target: expected) else {
            candidate = nil
            failure = .degenerate
            stage = .failed
            return
        }
        candidate = fit

        // With five points for six parameters, one bad touch can't hide completely: it
        // still lands noticeably off its target after the fit.
        let residuals = residualsMM(fit.transform)
        if let worst = residuals.indices.max(by: { residuals[$0] < residuals[$1] }),
           residuals[worst] > Self.outlierThresholdMM {
            failure = .outlier(index: worst, mm: residuals[worst])
            stage = .failed
        } else {
            stage = .review
        }
    }

    private func restart() {
        rawSamples = []
        candidate = nil
        showHoldHint = false
        stage = .collecting
    }

    /// Distance in mm between each target and where its sample lands under `t`.
    /// Empty if the panel's physical size is unknown.
    private func residualsMM(_ t: CGAffineTransform) -> [Double] {
        guard let physical = screen?.nativePhysicalSize, physical.width > 0, physical.height > 0 else { return [] }
        return zip(rawSamples, Self.targets).map { raw, target in
            let p = touchManager.relativeScreenPoint(forDigitizerPoint: raw, calibration: t, locationID: locationID)
            return Double(hypot((p.x - target.x) * physical.width, (p.y - target.y) * physical.height))
        }
    }

    /// Mean/max distance in mm between targets and where the samples land — before and after.
    private var errorSummary: String {
        guard let candidate else { return "" }
        let before = residualsMM(.identity)
        let after = residualsMM(candidate.transform)
        guard !before.isEmpty else { return "" }
        func mean(_ d: [Double]) -> Double { d.reduce(0, +) / Double(d.count) }
        return String(format: "Average error %.1f mm → %.1f mm   (worst %.1f mm → %.1f mm)",
                      mean(before), mean(after), before.max() ?? 0, after.max() ?? 0)
    }


    // MARK: Helpers

    private func position(of raw: CGPoint, calibration: CGAffineTransform, in size: CGSize) -> CGPoint {
        let p = touchManager.relativeScreenPoint(forDigitizerPoint: raw, calibration: calibration, locationID: locationID)
        return CGPoint(x: p.x * size.width, y: p.y * size.height)
    }

    private func touchButton(_ id: String, _ title: String, prominent: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .padding(.horizontal, 36)
                .padding(.vertical, 18)
                .background(RoundedRectangle(cornerRadius: 14)
                    .fill(prominent ? Color.accentColor : Color(white: 0.22)))
                .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .background(GeometryReader { g in
            Color.clear.preference(key: ButtonFrameKey.self,
                                   value: [id: g.frame(in: .named("calibration"))])
        })
    }
}


private struct ButtonFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}


private struct Crosshair: View {
    enum Kind { case pending, active, done }
    let state: Kind
    let size: CGFloat
    /// How far the current hold has got, 0…1. Replaces the pulse while a finger is holding.
    let progress: Double

    @State private var pulse = false

    var color: Color {
        switch state {
        case .pending: return Color(white: 0.3)
        case .active:  return .white
        case .done:    return Color(white: 0.45)
        }
    }

    var body: some View {
        ZStack {
            Rectangle().frame(width: size, height: 1.5)
            Rectangle().frame(width: 1.5, height: size)
            Circle().stroke(lineWidth: 1.5).frame(width: size * 0.5, height: size * 0.5)
            if state == .active {
                Circle()
                    .stroke(Color.accentColor, lineWidth: 3)
                    .frame(width: size, height: size)
                    .scaleEffect(pulse ? 1.25 : 0.85)
                    .opacity(progress > 0 ? 0 : (pulse ? 0.2 : 1))
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size, height: size)
            }
        }
        .foregroundColor(color)
        .frame(width: size * 1.4, height: size * 1.4)
    }
}
