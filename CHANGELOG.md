## 1.0.1

macOS AppKit tray lifecycle and click-responsiveness fixes (with zero modifications to the Linux and Windows backends).

### macOS (`platform/macos/`)
* **Automatic Status Bar Cleanup on OS Termination (`TrayCoreTerminateObserver`)**: Observe `NSApplicationWillTerminateNotification` using a Hot-Restart-safe Objective-C observer (`class_replaceMethod`) so `MacOSTrayBackend` automatically calls `dispose()` (`[[NSStatusBar systemStatusBar] removeStatusItem:]`) when the application exits via Dock Quit or `Cmd+Q`.
* **Immediate Flutter Run-Loop Wakeup on Menu Click**: Schedule `Timer.run` + guarded `WidgetsBinding.instance..ensureVisualUpdate()..scheduleFrame()` inside `TrayCoreMenuTarget.onTrayMenuItemClicked:` so async menu click handlers execute immediately after returning from `NativeCallable.isolateLocal`.

## 1.0.0

* Initial stable release of **`tray_core`** (`1.0.0`) — pure-Dart and FFI cross-platform desktop system tray and popup menu engine across **Linux**, **macOS**, and **Windows** with zero C++/CMake/Swift plugin wrappers and zero dependency on `tray_manager`, `nativeapi`, or `native_core`.
* **Symmetric 3-OS Architecture (`TrayBackend.forCurrentPlatform(applicationId: ..., windowsIconId: ...)`)**:
  * **Linux (`LinuxDbusTrayBackend`, `TrayDbusMenuObject`, `checkLinuxTraySupport`)**: Pure-Dart `org.kde.StatusNotifierItem` + `com.canonical.dbusmenu` implementation over `dbus` (`^0.8.0`) with inline PNG `icon-data`, ARGB32 `IconPixmap` decoding, Wayland `$XDG_RUNTIME_DIR/bus` trailing-slash normalization, GNOME AppIndicator auto-remediation, and `NameOwnerChanged` watcher re-registration.
  * **macOS (`MacOSTrayBackend`, `setMacOSMenuItemImageVisibility`)**: Cached Objective-C runtime (`libobjc.A.dylib`) bindings for `NSStatusBar`, `NSStatusItem`, `NSMenu`, and `NSMenuItem`, sanitized UTF-8 marshaling with `@""` fallback, template `NSImage` rendering, `class_replaceMethod` Hot Restart-safe menu click rebinding, and macOS 27+ `preferredImageVisibility` runtime-guarded visibility.
  * **Windows (`WindowsTrayBackend`)**: Cached Win32 bindings with `HWND`-keyed message dispatch, Hot Restart-safe `DefWindowProcW` class registration + per-`HWND` `GWLP_WNDPROC` binding/restoration, configurable `iconId` (`NOTIFYICONDATAW.uID`), full `976`-byte (64-bit) / `956`-byte (32-bit) `NOTIFYICONDATAW` ABI struct, top-level `WS_EX_TOOLWINDOW | WS_POPUP` host window, synchronous foreground ownership claim on left-click (`WM_LBUTTONUP` / `NIN_SELECT` / `NIN_KEYSELECT`), `TaskbarCreated` recovery, `PostMessageW(..., WM_NULL)` dismissal, and `32×32` Premultiplied BGRA `CreateDIBSection` `HBITMAP` menu icons attached strictly after `AppendMenuW`.
