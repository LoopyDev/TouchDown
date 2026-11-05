# TouchDown

Use a USB touchscreen with your Mac: tap to click, swipe to scroll, pinch to zoom. If a touchscreen works on Windows, it should work with TouchDown.

TouchDown is a fork of [Touch Up](https://github.com/shueber/Touch-Up) by Sebastian Hueber (RWTH Aachen). It fixes screens that Touch Up detects but that don't respond to touch, and adds calibration.

## Install

1. Download `TouchDown.app` from the [latest release](https://github.com/LoopyDev/TouchDown/releases) and move it to your Applications folder.
2. Open it. TouchDown isn't signed by Apple, so macOS blocks the first launch. Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. On macOS 14 and earlier you can also right-click the app and choose **Open**.
3. When asked, turn TouchDown on in **System Settings → Privacy & Security → Accessibility**. Then quit TouchDown from its menu bar icon and open it again.
4. Plug in your touchscreen and touch it.

Requires macOS 12 or later. To start TouchDown automatically, add it under **System Settings → General → Login Items**.

## Using it

- **Tap** to click; rest one finger and **tap with a second** to right-click
- **Swipe** to scroll, **rest your finger, then move** to drag
- **Pinch** to zoom

TouchDown lives in the menu bar. Under **Settings** you can change these gestures and, for each connected touchscreen:

- choose which display it controls
- **Test** it: circles show where the screen reports your fingers
- **Calibrate** it, if touches land beside your finger: touch and hold five targets, try the result, then save

Settings stay with the touchscreen, even if you plug it into a different USB port.

## Troubleshooting

**The screen shows up in Settings, but touching does nothing.**
Open **Test** and touch the screen.
- *Circles appear:* TouchDown is getting touches but isn't allowed to control the pointer. In Accessibility settings, switch TouchDown off and on, then reopen it.
- *No circles:* unplug the screen, plug it back in and try again. If that doesn't help, please [report it](#reporting-a-screen-that-doesnt-work).

**macOS keeps asking for Accessibility, even though it's switched on.**
macOS has kept a permission for an older copy of the app. Quit TouchDown, run this in Terminal, then open TouchDown and allow access again:
```
tccutil reset All io.github.loopydev.TouchDown
```

**Every touch clicks twice, or the pointer jumps around.**
Make sure only one copy is running, and that Touch Up isn't running alongside TouchDown.

**Touches land a little beside your finger.** Use **Calibrate** in Settings.

**The screen isn't listed in Settings at all.** It may not identify itself as a standard touchscreen. Please report it.

## Reporting a screen that doesn't work

[Open an issue](https://github.com/LoopyDev/TouchDown/issues/new) with:
- the touchscreen's make and model, and the name shown in TouchDown's Settings
- your macOS version and Mac model
- what you tried from Troubleshooting, and whether circles appear in **Test**

## Building from source

You need Xcode. To build, install to `/Applications` and launch:
```
scripts/install-local.sh
```
Each build is signed ad-hoc, which macOS treats as a new app, so you'll be asked for Accessibility again after every rebuild. To avoid that, sign with a certificate from your keychain, such as the free Apple Development certificate Xcode creates for your Apple ID:
```
SIGN_IDENTITY="Apple Development" scripts/install-local.sh
```

The touch handling lives in the `TouchUpCore` framework, which you can also use in your own app to get raw multitouch data. It keeps its original name so fixes can be shared with Touch Up.

## License

MIT, like Touch Up. See [LICENSE](LICENSE).
