# TouchUpCore

The framework behind TouchDown. It reads any Windows-compatible USB touchscreen and gives your Mac app live multitouch data: every finger's position, phase and ID. Use it for games, research or prototypes. Optionally, it also turns touches into mouse events, which is what the TouchDown app uses it for.

It comes from [Touch Up](https://github.com/shueber/Touch-Up) and keeps its original name and API, so code written for Touch Up's framework works unchanged.

## Getting touches

Create a `TUCTouchInputManager`, give it a delegate and call `start()`. After every update, `touchesDidChange()` is called and `touchSet` holds the current touches.

```swift
import AppKit
import TouchUpCore

final class TouchReader: NSObject, TUCTouchDelegate {
    let manager = TUCTouchInputManager()

    func start() {
        manager.postMouseEvents = false   // raw touches only: no clicks, no Accessibility needed
        manager.delegate = self
        manager.start()
    }

    // Called after every update of `touchSet`.
    func touchesDidChange() {
        let touches = (manager.touchSet.allObjects as! [TUCTouch]).filter { $0.isActive() }
        for touch in touches {
            // `location` is relative to the screen (0…1, origin top left).
            print(touch.contactID, touch.location, touch.phase.rawValue)
        }
    }

    func touchscreenDidConnect(withLocationID locationID: UInt32) {}
    func touchscreenDidDisconnect(withLocationID locationID: UInt32) {}

    // Which display this touchscreen sits on; touch locations are relative to it.
    func touchscreen(forLocationID locationID: UInt32) -> TUCScreen? {
        TUCScreen.allScreens().last
    }

    // Only consulted when `postMouseEvents` is on.
    func action(for gesture: TUCCursorGesture) -> TUCCursorAction { .none }

    func digitizerRotation(forLocationID locationID: UInt32) -> CGFloat { 0 }
}
```

Each `TUCTouch` has:
- `location`: where the finger is, relative to the touchscreen's display; `rawLocation` is what the hardware reported
- `phase`: began, moved, stationary, ended or cancelled
- `uuid`, unique per touch, and `contactID`, the hardware's slot number, which gets reused
- `locationID`: which touchscreen it came from, if several are connected

Up to four touchscreens can be connected at once. Each is identified by its `locationID` in the delegate calls.

## Turning touches into mouse events

Leave `postMouseEvents` on (the default) and the manager recognises gestures and posts mouse events itself. Return the `TUCCursorAction` you want for each `TUCCursorGesture` from `action(for:)`, for example `.click` for a tap or `.scroll` for a drag. Timing and tolerances such as `holdDuration`, `doubleClickTolerance` and `stationaryThreshold` are properties on the manager. The TouchDown app's `TouchUp.swift` is a complete example.

Posting mouse events needs Accessibility permission. In a sandboxed app, also request post-event access with `CGRequestPostEventAccess()`; without it, the events are silently dropped.

## Optional delegate methods

- `digitizerCalibration(forLocationID:)`: an affine correction for a touchscreen that doesn't line up with its display, applied before rotation and screen mapping.

## Requirements

- macOS 12 or later
- A sandboxed app needs the `com.apple.security.device.usb` entitlement to read the touchscreen.
