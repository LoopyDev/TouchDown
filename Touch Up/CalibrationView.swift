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

    private enum Stage { case collecting, review, failed }

    @State private var stage: Stage = .collecting
    @State private var rawSamples: [CGPoint] = []          // one per completed target
    @State private var trackedTouch: UUID?
    @State private var trackedSamples: [CGPoint] = []      // raw positions of the current touch
    @State private var candidate: DigitizerCalibration?
    @State private var buttonFrames: [String: CGRect] = [:]

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
                      size: 12 * pixelsPerMM)
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
            Text("Touch the centre of each crosshair, hold still, then lift")
                .font(.system(size: 28, weight: .medium, design: .rounded))
            Text("\(min(index + 1, Self.targets.count)) of \(Self.targets.count)")
                .font(.system(size: 20, design: .rounded))
                .foregroundColor(.gray)
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
            Crosshair(state: .done, size: 12 * pixelsPerMM)
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
            Text("One of the touches was probably off-target. Let's go again.")
                .font(.system(size: 18, design: .rounded))
                .foregroundColor(.gray)
            HStack(spacing: 24) {
                touchButton("redo", "Start Over", prominent: true) { restart() }
                    .keyboardShortcut(.defaultAction)
                touchButton("cancel", "Cancel") { finish(nil) }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }


    // MARK: Touch handling

    private var liveTouches: [TUCTouch] {
        model.touches.filter { $0.locationID == locationID && $0.isActive() }
    }

    /// Follows one finger at a time. While it's down we collect raw samples; when it lifts we
    /// either record a calibration point or (in review) treat it as a tap on a button.
    private func handle(touches: [TUCTouch], size: CGSize) {
        let mine = touches.filter { $0.locationID == locationID }

        if let id = trackedTouch {
            if let touch = mine.first(where: { $0.uuid == id }), touch.isActive() {
                trackedSamples.append(touch.rawLocation)
            } else {
                let samples = trackedSamples
                trackedTouch = nil
                trackedSamples = []
                touchLifted(samples: samples, size: size)
            }
        } else if let touch = mine.first(where: { $0.isActive() }) {
            trackedTouch = touch.uuid
            trackedSamples = [touch.rawLocation]
        }
    }

    private func touchLifted(samples: [CGPoint], size: CGSize) {
        guard let point = Self.settledPoint(of: samples) else { return }

        switch stage {
        case .collecting:
            rawSamples.append(point)
            if rawSamples.count == Self.targets.count {
                computeCandidate()
            }

        case .review, .failed:
            // Mouse events are off during calibration, so make the buttons touchable directly.
            let calibration = stage == .review ? (candidate?.transform ?? .identity) : .identity
            let p = position(of: point, calibration: calibration, in: size)
            if buttonFrames["save"]?.contains(p) == true, stage == .review {
                finish(candidate)
            } else if buttonFrames["redo"]?.contains(p) == true {
                restart()
            } else if buttonFrames["cancel"]?.contains(p) == true {
                finish(nil)
            }
        }
    }

    /// The finger lands, wobbles, settles, and smears slightly on lift. Ignore the first
    /// third and take a per-axis median of the rest. Very short contacts are discarded.
    static func settledPoint(of samples: [CGPoint]) -> CGPoint? {
        guard samples.count >= 3 else { return nil }
        let settled = samples.dropFirst(samples.count / 3)
        func median(_ v: [CGFloat]) -> CGFloat {
            let s = v.sorted()
            return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
        }
        return CGPoint(x: median(settled.map(\.x)), y: median(settled.map(\.y)))
    }


    // MARK: Fit

    private func computeCandidate() {
        // Express each on-screen target in raw digitizer space (undoing rotation/letterbox),
        // so the correction lives in the digitizer's own frame.
        let expected = Self.targets.map {
            touchManager.digitizerPoint(forRelativeScreenPoint: $0, locationID: locationID)
        }
        if let fit = DigitizerCalibration.fit(raw: rawSamples, target: expected) {
            candidate = fit
            stage = .review
        } else {
            stage = .failed
        }
    }

    private func restart() {
        rawSamples = []
        candidate = nil
        stage = .collecting
    }

    /// Mean/max distance in mm between targets and where the samples land — before and after.
    private var errorSummary: String {
        guard let screen, let candidate else { return "" }
        let physical = screen.nativePhysicalSize

        func errors(_ t: CGAffineTransform) -> (mean: Double, max: Double) {
            let d = zip(rawSamples, Self.targets).map { raw, target -> Double in
                let p = touchManager.relativeScreenPoint(forDigitizerPoint: raw, calibration: t, locationID: locationID)
                let dx = Double((p.x - target.x) * physical.width)
                let dy = Double((p.y - target.y) * physical.height)
                return (dx * dx + dy * dy).squareRoot()
            }
            return (d.reduce(0, +) / Double(max(d.count, 1)), d.max() ?? 0)
        }

        let before = errors(.identity)
        let after = errors(candidate.transform)
        return String(format: "Average error %.1f mm → %.1f mm   (worst %.1f mm → %.1f mm)",
                      before.mean, after.mean, before.max, after.max)
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
                    .opacity(pulse ? 0.2 : 1)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
            }
        }
        .foregroundColor(color)
        .frame(width: size * 1.4, height: size * 1.4)
    }
}
