# tray_core

[![Pub Version](https://img.shields.io/pub/v/tray_core)](https://pub.dev/packages/tray_core)
[![Native Plugins](https://img.shields.io/badge/native%20plugins-zero-brightgreen)](https://pub.dev/packages/tray_core)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](https://github.com/infradise/tray_core/blob/main/LICENSE)

Pure-Dart and FFI cross-platform desktop system tray and popup menu engine for Flutter across **Linux**, **macOS**, and **Windows** — built without C++/CMake/Swift plugin wrappers and with zero dependency on `tray_manager` or `nativeapi`.

| Platform | Support | Protocol / Native API |
| :--- | :--- | :--- |
| Linux | KDE, GNOME, Ubuntu, XFCE, Waybar | Pure-Dart `org.kde.StatusNotifierItem` + `com.canonical.dbusmenu` (`dbus`) |
| macOS | macOS 13.0+ (`arm64` & `x86_64`, incl. macOS 27+) | `NSStatusBar`, `NSStatusItem`, `NSMenu`, `preferredImageVisibility` |
| Windows | Windows 10 / 11 (`x64` & `arm64`) | `Shell_NotifyIconW` (`976B` ABI), `TrackPopupMenu`, 32-bit Premultiplied BGRA DIB `HBITMAP` |

## Platform Capability Matrix

| Capability | Linux (`SNI` / `DBusMenu`) | macOS (`AppKit`) | Windows (`Win32`) |
| :--- | :---: | :---: | :---: |
| System tray icon & tooltip (`create`) | ✅ (`IconPixmap` + `IconThemePath`) | ✅ (`NSImage` template icon) | ✅ (`.ico` via `LoadImageW`) |
| Primary click callback (`onIconClicked`) | ✅ (`Activate`) | Opens attached `NSMenu` (OS convention) | ✅ (`WM_LBUTTONUP` / `NIN_SELECT` / `NIN_KEYSELECT`) |
| Context menu & leading item icons (`setMenu` / `setMenuIcons`) | ✅ (Inline PNG `icon-data`) | ✅ (macOS 13–26 + macOS 27+ `preferredImageVisibility`) | ✅ (`32×32` Premultiplied BGRA DIB `HBITMAP`) |
| In-place label/enabled updates without rebuild (`trayMenuSignature`) | ✅ (`ItemsPropertiesUpdated`) | ✅ (`setTitle:` / `setEnabled:`) | ✅ (`SetMenuItemInfoW`) |
| Panel / Explorer restart resilience | ✅ (`NameOwnerChanged` subscriber) | Managed by WindowServer | ✅ (`TaskbarCreated` re-registration) |
| Multi-instance icon isolation (`windowsIconId`) | Automatic (`pid-counter` bus name) | Managed per process | ✅ (`NOTIFYICONDATAW.uID`) |

## Features

- **Unified Factory (`TrayBackend.forCurrentPlatform()`)**: Automatically instantiates the symmetric OS backend (`LinuxDbusTrayBackend`, `MacOSTrayBackend`, or `WindowsTrayBackend`), supporting optional `applicationId` (Linux) and `windowsIconId` (Windows).
- **Linux (`LinuxDbusTrayBackend` & `checkLinuxTraySupport`)**:
  - Exports `org.kde.StatusNotifierItem` and `com.canonical.dbusmenu` with inline PNG `icon-data` byte arrays and in-place property diffs (`ItemsPropertiesUpdated`).
  - Automatically detects and enables installed GNOME Shell AppIndicator extensions and subscribes to `NameOwnerChanged` for dynamic panel restarts.
- **macOS (`MacOSTrayBackend` & `setMacOSMenuItemImageVisibility`)**:
  - Uses sanitized UTF-8 marshaling (`Utf8Codec(allowMalformed: true)`) with `@""` fallback so localized or emoji titles never trigger AppKit `NSParameterAssert(aString != nil)` crashes.
  - Enforces `NSMenuItem.preferredImageVisibility = .visible (1)` on macOS 27+ while remaining runtime-guarded on macOS 13 Ventura through macOS 26 Tahoe, with `class_replaceMethod` Hot Restart-safe click target rebinding.
- **Windows (`WindowsTrayBackend`)**:
  - Uses the full `976`-byte (64-bit) / `956`-byte (32-bit) `NOTIFYICONDATAW` ABI struct, a hidden top-level `WS_EX_TOOLWINDOW | WS_POPUP` host window (Hot Restart-safe `DefWindowProcW` class registration + per-`HWND` `GWLP_WNDPROC`, `PostMessageW(..., WM_NULL)` dismissal, and `TaskbarCreated` Explorer-restart recovery), and `32×32` Premultiplied BGRA `CreateDIBSection` `HBITMAP` menu icons attached strictly after `AppendMenuW`.

## Installation

```yaml
dependencies:
  tray_core: ^1.0.0
```

## Quick Start

```dart
import 'package:tray_core/tray_core.dart';

enum AppTrayIcon { open, quit }

Future<void> setupTray(String iconPath) async {
  final tray = TrayBackend<AppTrayIcon>.forCurrentPlatform(
    applicationId: 'desktop-workspace',
  );
  final created = await tray.create(
    iconPath: iconPath,
    tooltip: 'Workspace Agent',
    onIconClicked: () {},
    onItemSelected: (id) {
      if (id == 'quit') tray.dispose();
    },
  );
  if (created) {
    tray.setMenu(const <TrayMenuEntry<AppTrayIcon>>[
      TrayMenuItemEntry(
        id: 'open',
        label: 'Open Workspace',
        icon: AppTrayIcon.open,
      ),
      TrayMenuSeparatorEntry(),
      TrayMenuItemEntry(id: 'quit', label: 'Quit', icon: AppTrayIcon.quit),
    ]);
  }
}
```

## License

Apache License 2.0 — Copyright 2026 Infradise Inc. See [LICENSE](LICENSE).
