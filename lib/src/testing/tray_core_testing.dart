/// Internal test-only barrel exposing platform ABI constants, UTF-8 marshaling
/// helpers, and live OS menu/DIB round-trip probes for `test/`.
library;

export '../ffi/tray_native_memory.dart' show withNullTerminatedUtf8;
export '../platform/macos/macos_tray_backend.dart'
    show debugCreateMacOSMenuItemTitleRoundTrip;
export '../platform/windows/windows_dib_menu_bitmap.dart'
    show WindowsDibProbeResult, debugCreateWindowsMenuDibRoundTrip;
export '../platform/windows/windows_notify_icon_abi.dart'
    show
        debugWin32NotifyIconDataWSize,
        kNinKeySelect,
        kNinSelect,
        kWmLButtonUp,
        kWmRButtonUp;
export '../platform/windows/windows_tray_backend.dart'
    show isWindowsTrayPrimarySelectEvent;
