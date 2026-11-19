import 'dart:ffi' as ffi;
import 'dart:io';

import '../../ffi/tray_native_memory.dart';

/// Custom tray callback message (`WM_APP + 1 == 0x8001`).
const int kWmTrayIcon = 0x8001;

/// `WM_NULL` (`0x0000`).
const int kWmNull = 0x0000;

/// `WM_DESTROY` (`0x0002`).
const int kWmDestroy = 0x0002;

const int _kGwlpWndProc = -4;

/// `WM_CONTEXTMENU` (`0x007B`).
const int kWmContextMenu = 0x007B;

/// `WM_LBUTTONUP` (`0x0202`).
const int kWmLButtonUp = 0x0202;

/// `WM_RBUTTONUP` (`0x0205`).
const int kWmRButtonUp = 0x0205;

/// `NIN_SELECT` (`WM_USER + 0 == 0x0400`).
const int kNinSelect = 0x0400;

/// `NIN_KEYSELECT` (`WM_USER + 1 == 0x0401`, keyboard Space/Enter activation).
const int kNinKeySelect = 0x0401;

/// `WS_EX_TOOLWINDOW` (`0x00000080`).
const int kWsExToolWindow = 0x00000080;

/// `WS_POPUP` (`0x80000000`).
const int kWsPopup = 0x80000000;

/// `MSGFLT_ALLOW` (`1`).
const int kMsgFltAllow = 1;

/// `NIM_ADD` (`0x00`) and `NIM_DELETE` (`0x02`).
const int kNimAdd = 0x00;

/// `NIM_DELETE` (`0x02`).
const int kNimDelete = 0x02;

/// `NIF_MESSAGE | NIF_ICON | NIF_TIP` (`0x01 | 0x02 | 0x04`).
const int kNifStandardFlags = 0x01 | 0x02 | 0x04;

/// `MF_STRING` (`0x0000`), `MF_GRAYED` (`0x0001`), `MF_DISABLED` (`0x0002`),
/// `MF_SEPARATOR` (`0x0800`).
const int kMfString = 0x0000;

/// `MF_GRAYED | MF_DISABLED` (`0x0003`).
const int kMfDisabledFlags = 0x0001 | 0x0002;

/// `MF_SEPARATOR` (`0x0800`).
const int kMfSeparator = 0x0800;

/// `MIIM_STATE | MIIM_STRING` (`0x0001 | 0x0040`).
const int kMiimStateAndString = 0x0001 | 0x0040;

/// `MIIM_BITMAP` (`0x00000080`).
const int kMiimBitmap = 0x00000080;

/// `TPM_RETURNCMD | TPM_RIGHTBUTTON` (`0x0100 | 0x0002`).
const int kTpmTrayFlags = 0x0100 | 0x0002;

/// `IMAGE_ICON` (`1`) and `LR_LOADFROMFILE | LR_DEFAULTSIZE` (`0x0050`).
const int kImageIcon = 1;

/// `LR_LOADFROMFILE | LR_DEFAULTSIZE` (`0x0010 | 0x0040`).
const int kLrLoadFileDefaultSize = 0x0010 | 0x0040;

/// Native Win32 `POINT` ABI layout.
final class Win32TrayPoint extends ffi.Struct {
  /// Screen X coordinate.
  @ffi.Int32()
  external int x;

  /// Screen Y coordinate.
  @ffi.Int32()
  external int y;
}

/// Native Win32 `MENUITEMINFOW` ABI layout.
final class Win32MenuItemInfoW extends ffi.Struct {
  /// Struct byte size (`sizeof(MENUITEMINFOW)`).
  @ffi.Uint32()
  external int cbSize;

  /// `MIIM_*` mask flags.
  @ffi.Uint32()
  external int fMask;

  /// Menu item type flags.
  @ffi.Uint32()
  external int fType;

  /// Menu item state (`MFS_ENABLED` / `MFS_DISABLED`).
  @ffi.Uint32()
  external int fState;

  /// Command identifier (`wID`).
  @ffi.Uint32()
  external int wID;

  /// Optional submenu `HMENU`.
  external ffi.Pointer<ffi.Void> hSubMenu;

  /// Optional checked bitmap.
  external ffi.Pointer<ffi.Void> hbmpChecked;

  /// Optional unchecked bitmap.
  external ffi.Pointer<ffi.Void> hbmpUnchecked;

  /// Application-defined item data.
  @ffi.UintPtr()
  external int dwItemData;

  /// UTF-16 item label buffer.
  external ffi.Pointer<ffi.Uint16> dwTypeData;

  /// Character length of [dwTypeData].
  @ffi.Uint32()
  external int cch;

  /// Item icon `HBITMAP` (`MIIM_BITMAP`).
  external ffi.Pointer<ffi.Void> hbmpItem;
}

/// Native Win32 `BITMAPINFOHEADER` ABI layout (`40` bytes).
final class Win32BitmapInfoHeader extends ffi.Struct {
  /// Header byte size (`40`).
  @ffi.Uint32()
  external int biSize;

  /// Bitmap width in pixels.
  @ffi.Int32()
  external int biWidth;

  /// Bitmap height in pixels (negative for top-down DIB).
  @ffi.Int32()
  external int biHeight;

  /// Color plane count (`1`).
  @ffi.Uint16()
  external int biPlanes;

  /// Bits per pixel (`32`).
  @ffi.Uint16()
  external int biBitCount;

  /// Compression mode (`BI_RGB == 0`).
  @ffi.Uint32()
  external int biCompression;

  /// Raw pixel buffer byte size.
  @ffi.Uint32()
  external int biSizeImage;

  /// Horizontal resolution.
  @ffi.Int32()
  external int biXPelsPerMeter;

  /// Vertical resolution.
  @ffi.Int32()
  external int biYPelsPerMeter;

  /// Palette entries used.
  @ffi.Uint32()
  external int biClrUsed;

  /// Important palette entries.
  @ffi.Uint32()
  external int biClrImportant;
}

/// Native GDI `BITMAP` ABI layout queried by `GetObjectW(hBitmap, ...)`.
final class Win32Bitmap extends ffi.Struct {
  /// Bitmap type (`0`).
  @ffi.Int32()
  external int bmType;

  /// Width in pixels.
  @ffi.Int32()
  external int bmWidth;

  /// Height in pixels.
  @ffi.Int32()
  external int bmHeight;

  /// Row stride in bytes.
  @ffi.Int32()
  external int bmWidthBytes;

  /// Color planes (`1`).
  @ffi.Uint16()
  external int bmPlanes;

  /// Bits per pixel (`32`).
  @ffi.Uint16()
  external int bmBitsPixel;

  /// Pointer to DIB section pixel bits.
  external ffi.Pointer<ffi.Uint8> bmBits;
}

/// Native Win32 `WNDCLASSEXW` ABI layout.
final class Win32WndClassExW extends ffi.Struct {
  /// Struct byte size (`sizeof(WNDCLASSEXW)`).
  @ffi.Uint32()
  external int cbSize;

  /// Class style bitmask.
  @ffi.Uint32()
  external int style;

  /// Window procedure pointer (`WNDPROC`).
  external ffi.Pointer<ffi.Void> lpfnWndProc;

  /// Extra class bytes.
  @ffi.Int32()
  external int cbClsExtra;

  /// Extra window bytes.
  @ffi.Int32()
  external int cbWndExtra;

  /// Module `HINSTANCE`.
  external ffi.Pointer<ffi.Void> hInstance;

  /// Class large icon.
  external ffi.Pointer<ffi.Void> hIcon;

  /// Class cursor.
  external ffi.Pointer<ffi.Void> hCursor;

  /// Background `HBRUSH`.
  external ffi.Pointer<ffi.Void> hbrBackground;

  /// Default menu resource name.
  external ffi.Pointer<ffi.Uint16> lpszMenuName;

  /// Registered UTF-16 class name.
  external ffi.Pointer<ffi.Uint16> lpszClassName;

  /// Class small icon.
  external ffi.Pointer<ffi.Void> hIconSm;
}

/// Full Win32 `NOTIFYICONDATAW` ABI layout (`976` bytes on 64-bit, `956` bytes
/// on 32-bit).
final class Win32NotifyIconDataW extends ffi.Struct {
  /// Struct byte size (`976` on 64-bit, `956` on 32-bit).
  @ffi.Uint32()
  external int cbSize;

  /// Receiver host `HWND`.
  external ffi.Pointer<ffi.Void> hWnd;

  /// Application-defined tray icon ID.
  @ffi.Uint32()
  external int uID;

  /// `NIF_*` flags.
  @ffi.Uint32()
  external int uFlags;

  /// Callback message ID ([kWmTrayIcon]).
  @ffi.Uint32()
  external int uCallbackMessage;

  /// Loaded `HICON`.
  external ffi.Pointer<ffi.Void> hIcon;

  /// UTF-16 tooltip (`WCHAR[128]`).
  @ffi.Array(128)
  external ffi.Array<ffi.Uint16> szTip;

  /// Icon state flags.
  @ffi.Uint32()
  external int dwState;

  /// Icon state mask.
  @ffi.Uint32()
  external int dwStateMask;

  /// Balloon notification body (`WCHAR[256]`).
  @ffi.Array(256)
  external ffi.Array<ffi.Uint16> szInfo;

  /// Balloon timeout or `NOTIFYICON_VERSION_4`.
  @ffi.Uint32()
  external int uTimeoutOrVersion;

  /// Balloon notification title (`WCHAR[64]`).
  @ffi.Array(64)
  external ffi.Array<ffi.Uint16> szInfoTitle;

  /// Balloon info flags.
  @ffi.Uint32()
  external int dwInfoFlags;

  /// `GUID.Data1`.
  @ffi.Uint32()
  external int guidData1;

  /// `GUID.Data2`.
  @ffi.Uint16()
  external int guidData2;

  /// `GUID.Data3`.
  @ffi.Uint16()
  external int guidData3;

  /// `GUID.Data4`.
  @ffi.Array(8)
  external ffi.Array<ffi.Uint8> guidData4;

  /// Optional custom balloon `HICON`.
  external ffi.Pointer<ffi.Void> hBalloonIcon;
}

/// Byte size of the Win32 [Win32NotifyIconDataW] struct exposed for ABI
/// regression testing (`976` bytes on 64-bit, `956` bytes on 32-bit).
int get debugWin32NotifyIconDataWSize => ffi.sizeOf<Win32NotifyIconDataW>();

/// Native Win32 `WNDPROC` signature.
typedef Win32TrayWndProcNative =
    ffi.IntPtr Function(
      ffi.Pointer<ffi.Void> hwnd,
      ffi.Uint32 msg,
      ffi.UintPtr wParam,
      ffi.IntPtr lParam,
    );

/// Message handler callback registered per hidden tray host `HWND`.
typedef Win32TrayMessageHandler =
    bool Function(ffi.Pointer<ffi.Void> hwnd, int msg, int wParam, int lParam);

/// One-time cached Win32 (`user32.dll`, `kernel32.dll`, `shell32.dll`,
/// `gdi32.dll`) bindings and permanent `WNDPROC` dispatcher for `tray_core`.
///
/// Keeping [wndProcCallable] alive for the lifetime of the isolate ensures
/// re-creating tray backends (e.g. toggling System Tray OFF then ON) never
/// jumps into a closed `NativeCallable` registered on `TrayCoreHostWindow`.
class WindowsTrayBindings {
  WindowsTrayBindings._({
    required this.getModuleHandleW,
    required this.registerClassExW,
    required this.createWindowExW,
    required this.isWindow,
    required this.setWindowLongPtrW,
    required this.destroyWindow,
    required this.defWindowProcWPtr,
    required this.defWindowProcW,
    required this.registerWindowMessageW,
    required this.changeWindowMessageFilterEx,
    required this.shellNotifyIconW,
    required this.loadImageW,
    required this.destroyIcon,
    required this.createDIBSection,
    required this.getObjectW,
    required this.deleteObject,
    required this.createPopupMenu,
    required this.appendMenuW,
    required this.setMenuItemInfoW,
    required this.destroyMenu,
    required this.getCursorPos,
    required this.setForegroundWindow,
    required this.trackPopupMenu,
    required this.postMessageW,
    required this.scratchPoint,
    required this.scratchMii,
    required this.scratchNid,
  });

  static WindowsTrayBindings? _instance;
  static bool _attempted = false;

  static final Map<int, Win32TrayMessageHandler> _handlersByHwnd =
      <int, Win32TrayMessageHandler>{};

  /// Permanent isolate-local `WNDPROC` trampoline shared across all
  /// `TrayCoreHostWindow` instances.
  static final ffi.NativeCallable<Win32TrayWndProcNative> wndProcCallable =
      ffi.NativeCallable<Win32TrayWndProcNative>.isolateLocal(
        _dispatchWndProc,
        exceptionalReturn: 0,
      );

  static bool _windowClassRegistered = false;

  /// Returns the cached [WindowsTrayBindings] singleton on Windows, or `null`
  /// on other OSes.
  static WindowsTrayBindings? get instance {
    if (!Platform.isWindows) return null;
    if (_attempted) return _instance;
    _attempted = true;

    try {
      final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
      final user32 = ffi.DynamicLibrary.open('user32.dll');
      final shell32 = ffi.DynamicLibrary.open('shell32.dll');
      final gdi32 = ffi.DynamicLibrary.open('gdi32.dll');

      int Function(ffi.Pointer<ffi.Void>, int, int, ffi.Pointer<ffi.Void>)?
      msgFilterEx;
      try {
        msgFilterEx = user32.lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Void>,
            ffi.Uint32,
            ffi.Uint32,
            ffi.Pointer<ffi.Void>,
          ),
          int Function(ffi.Pointer<ffi.Void>, int, int, ffi.Pointer<ffi.Void>)
        >('ChangeWindowMessageFilterEx');
      } catch (_) {
        msgFilterEx = null;
      }

      final scratchPoint =
          TrayNativeMemory.malloc(
            ffi.sizeOf<Win32TrayPoint>(),
          ).cast<Win32TrayPoint>();
      final scratchMii =
          TrayNativeMemory.malloc(
            ffi.sizeOf<Win32MenuItemInfoW>(),
          ).cast<Win32MenuItemInfoW>();
      final scratchNid =
          TrayNativeMemory.malloc(
            ffi.sizeOf<Win32NotifyIconDataW>(),
          ).cast<Win32NotifyIconDataW>();

      if (scratchPoint == ffi.nullptr ||
          scratchMii == ffi.nullptr ||
          scratchNid == ffi.nullptr) {
        if (scratchPoint != ffi.nullptr) {
          TrayNativeMemory.free(scratchPoint.cast());
        }
        if (scratchMii != ffi.nullptr) TrayNativeMemory.free(scratchMii.cast());
        if (scratchNid != ffi.nullptr) TrayNativeMemory.free(scratchNid.cast());
        return null;
      }

      final setLongName =
          ffi.sizeOf<ffi.IntPtr>() == 8
              ? 'SetWindowLongPtrW'
              : 'SetWindowLongW';

      return _instance = WindowsTrayBindings._(
        getModuleHandleW: kernel32.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint16>),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint16>)
        >('GetModuleHandleW'),
        registerClassExW: user32.lookupFunction<
          ffi.Uint16 Function(ffi.Pointer<Win32WndClassExW>),
          int Function(ffi.Pointer<Win32WndClassExW>)
        >('RegisterClassExW'),
        createWindowExW: user32.lookupFunction<
          ffi.Pointer<ffi.Void> Function(
            ffi.Uint32,
            ffi.Pointer<ffi.Uint16>,
            ffi.Pointer<ffi.Uint16>,
            ffi.Uint32,
            ffi.Int32,
            ffi.Int32,
            ffi.Int32,
            ffi.Int32,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
          ),
          ffi.Pointer<ffi.Void> Function(
            int,
            ffi.Pointer<ffi.Uint16>,
            ffi.Pointer<ffi.Uint16>,
            int,
            int,
            int,
            int,
            int,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
          )
        >('CreateWindowExW'),
        isWindow: user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('IsWindow'),
        setWindowLongPtrW: user32.lookupFunction<
          ffi.IntPtr Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.IntPtr),
          int Function(ffi.Pointer<ffi.Void>, int, int)
        >(setLongName),
        destroyWindow: user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('DestroyWindow'),
        defWindowProcWPtr: user32.lookup<ffi.Void>('DefWindowProcW'),
        defWindowProcW: user32.lookupFunction<
          ffi.IntPtr Function(
            ffi.Pointer<ffi.Void>,
            ffi.Uint32,
            ffi.UintPtr,
            ffi.IntPtr,
          ),
          int Function(ffi.Pointer<ffi.Void>, int, int, int)
        >('DefWindowProcW'),
        registerWindowMessageW: user32.lookupFunction<
          ffi.Uint32 Function(ffi.Pointer<ffi.Uint16>),
          int Function(ffi.Pointer<ffi.Uint16>)
        >('RegisterWindowMessageW'),
        changeWindowMessageFilterEx: msgFilterEx,
        shellNotifyIconW: shell32.lookupFunction<
          ffi.Int32 Function(ffi.Uint32, ffi.Pointer<Win32NotifyIconDataW>),
          int Function(int, ffi.Pointer<Win32NotifyIconDataW>)
        >('Shell_NotifyIconW'),
        loadImageW: user32.lookupFunction<
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Uint16>,
            ffi.Uint32,
            ffi.Int32,
            ffi.Int32,
            ffi.Uint32,
          ),
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Uint16>,
            int,
            int,
            int,
            int,
          )
        >('LoadImageW'),
        destroyIcon: user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('DestroyIcon'),
        createDIBSection: gdi32.lookupFunction<
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<Win32BitmapInfoHeader>,
            ffi.Uint32,
            ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
            ffi.Pointer<ffi.Void>,
            ffi.Uint32,
          ),
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<Win32BitmapInfoHeader>,
            int,
            ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
            ffi.Pointer<ffi.Void>,
            int,
          )
        >('CreateDIBSection'),
        getObjectW: gdi32.lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Void>,
            ffi.Int32,
            ffi.Pointer<ffi.Void>,
          ),
          int Function(ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Void>)
        >('GetObjectW'),
        deleteObject: gdi32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('DeleteObject'),
        createPopupMenu: user32.lookupFunction<
          ffi.Pointer<ffi.Void> Function(),
          ffi.Pointer<ffi.Void> Function()
        >('CreatePopupMenu'),
        appendMenuW: user32.lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Void>,
            ffi.Uint32,
            ffi.UintPtr,
            ffi.Pointer<ffi.Uint16>,
          ),
          int Function(ffi.Pointer<ffi.Void>, int, int, ffi.Pointer<ffi.Uint16>)
        >('AppendMenuW'),
        setMenuItemInfoW: user32.lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Void>,
            ffi.Uint32,
            ffi.Int32,
            ffi.Pointer<Win32MenuItemInfoW>,
          ),
          int Function(
            ffi.Pointer<ffi.Void>,
            int,
            int,
            ffi.Pointer<Win32MenuItemInfoW>,
          )
        >('SetMenuItemInfoW'),
        destroyMenu: user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('DestroyMenu'),
        getCursorPos: user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<Win32TrayPoint>),
          int Function(ffi.Pointer<Win32TrayPoint>)
        >('GetCursorPos'),
        setForegroundWindow: user32.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)
        >('SetForegroundWindow'),
        trackPopupMenu: user32.lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Void>,
            ffi.Uint32,
            ffi.Int32,
            ffi.Int32,
            ffi.Int32,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
          ),
          int Function(
            ffi.Pointer<ffi.Void>,
            int,
            int,
            int,
            int,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
          )
        >('TrackPopupMenu'),
        postMessageW: user32.lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Void>,
            ffi.Uint32,
            ffi.UintPtr,
            ffi.IntPtr,
          ),
          int Function(ffi.Pointer<ffi.Void>, int, int, int)
        >('PostMessageW'),
        scratchPoint: scratchPoint,
        scratchMii: scratchMii,
        scratchNid: scratchNid,
      );
    } catch (_) {
      return null;
    }
  }

  /// `GetModuleHandleW`.
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint16>)
  getModuleHandleW;

  /// `RegisterClassExW`.
  final int Function(ffi.Pointer<Win32WndClassExW>) registerClassExW;

  /// `CreateWindowExW`.
  final ffi.Pointer<ffi.Void> Function(
    int,
    ffi.Pointer<ffi.Uint16>,
    ffi.Pointer<ffi.Uint16>,
    int,
    int,
    int,
    int,
    int,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
  )
  createWindowExW;

  /// `IsWindow`.
  final int Function(ffi.Pointer<ffi.Void>) isWindow;

  /// `SetWindowLongPtrW` / `SetWindowLongW`.
  final int Function(ffi.Pointer<ffi.Void>, int, int) setWindowLongPtrW;

  /// `DestroyWindow`.
  final int Function(ffi.Pointer<ffi.Void>) destroyWindow;

  /// Native process-lifetime `DefWindowProcW` symbol address.
  final ffi.Pointer<ffi.Void> defWindowProcWPtr;

  /// `DefWindowProcW`.
  final int Function(ffi.Pointer<ffi.Void>, int, int, int) defWindowProcW;

  /// `RegisterWindowMessageW`.
  final int Function(ffi.Pointer<ffi.Uint16>) registerWindowMessageW;

  /// Optional `ChangeWindowMessageFilterEx`.
  final int Function(ffi.Pointer<ffi.Void>, int, int, ffi.Pointer<ffi.Void>)?
  changeWindowMessageFilterEx;

  /// `Shell_NotifyIconW`.
  final int Function(int, ffi.Pointer<Win32NotifyIconDataW>) shellNotifyIconW;

  /// `LoadImageW`.
  final ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Uint16>,
    int,
    int,
    int,
    int,
  )
  loadImageW;

  /// `DestroyIcon`.
  final int Function(ffi.Pointer<ffi.Void>) destroyIcon;

  /// `CreateDIBSection`.
  final ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<Win32BitmapInfoHeader>,
    int,
    ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
    ffi.Pointer<ffi.Void>,
    int,
  )
  createDIBSection;

  /// `GetObjectW`.
  final int Function(ffi.Pointer<ffi.Void>, int, ffi.Pointer<ffi.Void>)
  getObjectW;

  /// `DeleteObject`.
  final int Function(ffi.Pointer<ffi.Void>) deleteObject;

  /// `CreatePopupMenu`.
  final ffi.Pointer<ffi.Void> Function() createPopupMenu;

  /// `AppendMenuW`.
  final int Function(ffi.Pointer<ffi.Void>, int, int, ffi.Pointer<ffi.Uint16>)
  appendMenuW;

  /// `SetMenuItemInfoW`.
  final int Function(
    ffi.Pointer<ffi.Void>,
    int,
    int,
    ffi.Pointer<Win32MenuItemInfoW>,
  )
  setMenuItemInfoW;

  /// `DestroyMenu`.
  final int Function(ffi.Pointer<ffi.Void>) destroyMenu;

  /// `GetCursorPos`.
  final int Function(ffi.Pointer<Win32TrayPoint>) getCursorPos;

  /// `SetForegroundWindow`.
  final int Function(ffi.Pointer<ffi.Void>) setForegroundWindow;

  /// `TrackPopupMenu`.
  final int Function(
    ffi.Pointer<ffi.Void>,
    int,
    int,
    int,
    int,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
  )
  trackPopupMenu;

  /// `PostMessageW`.
  final int Function(ffi.Pointer<ffi.Void>, int, int, int) postMessageW;

  /// Reusable `Win32TrayPoint` scratch buffer.
  final ffi.Pointer<Win32TrayPoint> scratchPoint;

  /// Reusable `Win32MenuItemInfoW` scratch buffer.
  final ffi.Pointer<Win32MenuItemInfoW> scratchMii;

  /// Reusable `Win32NotifyIconDataW` scratch buffer.
  final ffi.Pointer<Win32NotifyIconDataW> scratchNid;

  /// Creates a hidden top-level `WS_EX_TOOLWINDOW | WS_POPUP` host window and
  /// registers [handler] in the `HWND` dispatch map.
  ffi.Pointer<ffi.Void> createHiddenHostWindow(
    Win32TrayMessageHandler handler,
  ) {
    const className = 'TrayCoreHostWindow';
    final hInstance = getModuleHandleW(ffi.nullptr);
    return TrayNativeMemory.withUtf16(className, (classNamePtr) {
      if (!_windowClassRegistered) {
        final wcSize = ffi.sizeOf<Win32WndClassExW>();
        final wc = TrayNativeMemory.malloc(wcSize).cast<Win32WndClassExW>();
        try {
          TrayNativeMemory.zeroFill(wc.cast(), wcSize);
          // Register the class with process-lifetime `DefWindowProcW` so
          // Flutter Hot Restart never leaves `WNDCLASSEXW.lpfnWndProc` pointing
          // at a terminated isolate's trampoline during `CreateWindowExW`.
          wc.ref
            ..cbSize = wcSize
            ..lpfnWndProc = defWindowProcWPtr
            ..hInstance = hInstance
            ..lpszClassName = classNamePtr;
          registerClassExW(wc);
          _windowClassRegistered = true;
        } finally {
          TrayNativeMemory.free(wc.cast());
        }
      }

      final hwnd = createWindowExW(
        kWsExToolWindow,
        classNamePtr,
        classNamePtr,
        kWsPopup,
        0,
        0,
        0,
        0,
        ffi.nullptr,
        ffi.nullptr,
        hInstance,
        ffi.nullptr,
      );
      if (hwnd != ffi.nullptr) {
        _handlersByHwnd[hwnd.address] = handler;
        setWindowLongPtrW(
          hwnd,
          _kGwlpWndProc,
          wndProcCallable.nativeFunction.address,
        );
      }
      return hwnd;
    });
  }

  /// Unregisters [hwnd] from the message dispatch table, restores
  /// `DefWindowProcW`, and destroys the host window.
  void destroyHiddenHostWindow(ffi.Pointer<ffi.Void> hwnd) {
    if (hwnd == ffi.nullptr) return;
    _handlersByHwnd.remove(hwnd.address);
    if (isWindow(hwnd) != 0) {
      setWindowLongPtrW(hwnd, _kGwlpWndProc, defWindowProcWPtr.address);
      destroyWindow(hwnd);
    }
  }

  static int _dispatchWndProc(
    ffi.Pointer<ffi.Void> hwnd,
    int msg,
    int wParam,
    int lParam,
  ) {
    final win32 = _instance;
    if (win32 == null) return 0;
    if (msg == kWmDestroy) {
      _handlersByHwnd.remove(hwnd.address);
      win32.setWindowLongPtrW(
        hwnd,
        _kGwlpWndProc,
        win32.defWindowProcWPtr.address,
      );
      return win32.defWindowProcW(hwnd, msg, wParam, lParam);
    }
    final handler = _handlersByHwnd[hwnd.address];
    if (handler != null && handler(hwnd, msg, wParam, lParam)) {
      return 0;
    }
    return win32.defWindowProcW(hwnd, msg, wParam, lParam);
  }
}
