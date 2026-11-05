# TouchDown
**Universal user-level driver to support touchscreens on macOS**
<hr/>

TouchDown is a fork of [Touch Up](https://github.com/shueber/Touch-Up) by Sebastian Hueber (RWTH Aachen HCI). It keeps the same driver core and adds fixes and features for screens that didn't work with the original.

Most current touchscreens work with Microsoft Windows out-of-the-box as they implement a standardized communication via USB HID. However, nothing happens when connecting these screens to a Mac.
The goal of TouchDown is to provide a simple, general-purpose driver that enables plug-and-play support for touchscreens on macOS.
The code in this repository provides a user-space driver that reads and processes the HID data into a set of touches and different utilities to inject mouse events into the system.

## What's different from Touch Up
- **Works with screens that start up as a mouse.** Many touchscreens only report multitouch once the computer switches them into multi-input mode, which Windows does automatically. TouchDown does too, and ignores the screen's built-in mouse fallback instead of sometimes locking onto it.
- **Asks for every permission it needs.** Touch Up could be granted Accessibility and still have every click silently dropped, because sending mouse events needs a separate permission it never requested.
- **Touch calibration** for screens whose touch doesn't line up with the picture: touch and hold five targets, try the result, then save.
- **Settings follow the screen**, not the USB port it's plugged into.

## What can you do with this App?
The TouchDown **utility app** allows you to control your Mac with any connected touch screen. It supports clicks, dragging, scrolling, and pinch-to-zoom.
While the behavior of the driver is customizable, the default setting was inspired by iPadOS:

- Tap anywhere on the screen to click objects
- Scroll content by flicking over the screen
- Drag contents by briefly resting your finger before moving it
- Zoom content by pinching two fingers
- Secondary clicks can be performed with two fingers
- You can even enable touching a window to move it to the front like Stage Manager on iPadOS does


### Installing the App
- Compile the app or download the latest build from [Releases](https://github.com/LoopyDev/TouchDown/releases).
- Builds are not signed by Apple, so the first launch is blocked. Right-click the app and choose **Open**, or allow it in System Settings → Privacy & Security.
- If you wish, move the app into your Applications folder and add it as a Login item.
- Launch it and allow the access it asks for in System Settings → Privacy & Security → Accessibility.
- Plug in your touchscreen and start touching.

If you build it yourself, macOS ties these permissions to that exact build. After rebuilding you may need to switch TouchDown off and on again in the Accessibility list.


### Compatibility
TouchDown should work with any touchscreen that also works with Windows.
Screens tested so far:

- Iiyama TF3222MC and T2336MSC-B2 (tested with Touch Up)
- 3M C4667PW (tested with Touch Up)
- eGalax EXC3188




## The *TouchUpCore* Framework
Game developers, researchers, and others who need access to all touch data can also benefit from this project by integrating the TouchUpCore **framework** themselves. It provides simple access to all touches recognized on the touch surface, simplifying multitouch prototype development in macOS.

The TouchDown app itself is an example of integrating the TouchUpCore framework. You can have a look at the *DebugView* to see how you can visualize the different touch points. Remember that your app needs an Entitlement to access USB if running in the Sandbox.

The framework keeps its original name so fixes can still be shared with the upstream project.
