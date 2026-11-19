import 'dart:ffi' as ffi;

import '../../ffi/tray_native_memory.dart';
import '../../tray_backend.dart';
import '../../tray_menu_entry.dart';
import 'windows_dib_menu_bitmap.dart';
import 'windows_notify_icon_abi.dart';

class _WindowsTrayMenuItem {
  _WindowsTrayMenuItem({required this.commandId, required String label})
    : _label = label;

  final int commandId;
  ffi.Pointer<ffi.Void> parentMenu = ffi.nullptr;

  String _label;
  bool _isEnabled = true;
  ffi.Pointer<ffi.Void> _hBitmap = ffi.nullptr;
  void Function()? _onClicked;

  String get label => _label;

  set label(String value) {
    _label = value;
    if (parentMenu != ffi.nullptr) {
      _syncTextAndState();
    }
  }

  bool get isEnabled => _isEnabled;

  set isEnabled(bool value) {
    _isEnabled = value;
    if (parentMenu != ffi.nullptr) {
      _syncTextAndState();
    }
  }

  ffi.Pointer<ffi.Void> get bitmap => _hBitmap;

  set bitmap(ffi.Pointer<ffi.Void> value) {
    _hBitmap = value;
    if (parentMenu != ffi.nullptr) {
      _syncBitmap(value);
    }
  }

  void setClickListener(void Function() listener) {
    _onClicked = listener;
  }

  void invokeClick() => _onClicked?.call();

  void _syncTextAndState() {
    final win32 = WindowsTrayBindings.instance;
    if (win32 == null || parentMenu == ffi.nullptr) return;
    try {
      final mii = win32.scratchMii;
      final miiSize = ffi.sizeOf<Win32MenuItemInfoW>();
      TrayNativeMemory.zeroFill(mii.cast(), miiSize);
      TrayNativeMemory.withUtf16(_label, (wstr) {
        mii.ref
          ..cbSize = miiSize
          ..fMask = kMiimStateAndString
          ..fState = _isEnabled ? 0 : kMfDisabledFlags
          ..wID = commandId
          ..dwTypeData = wstr
          ..cch = _label.length;
        win32.setMenuItemInfoW(parentMenu, commandId, 0, mii);
      });
    } catch (_) {
      // Ignore transient menu item update error.
    }
  }

  void _syncBitmap(ffi.Pointer<ffi.Void> hBitmap) {
    final win32 = WindowsTrayBindings.instance;
    if (win32 == null || parentMenu == ffi.nullptr) return;
    try {
      final mii = win32.scratchMii;
      final miiSize = ffi.sizeOf<Win32MenuItemInfoW>();
      TrayNativeMemory.zeroFill(mii.cast(), miiSize);
      mii.ref
        ..cbSize = miiSize
        ..fMask = kMiimBitmap
        ..wID = commandId
        ..hbmpItem = hBitmap;
      win32.setMenuItemInfoW(parentMenu, commandId, 0, mii);
    } catch (_) {
      // Ignore transient menu bitmap update error.
    }
  }
}

class _WindowsTrayMenu {
  _WindowsTrayMenu(this.hMenu);

  final ffi.Pointer<ffi.Void> hMenu;
  final Map<int, _WindowsTrayMenuItem> itemsByCommandId =
      <int, _WindowsTrayMenuItem>{};

  static _WindowsTrayMenu? create() {
    final win32 = WindowsTrayBindings.instance;
    if (win32 == null) return null;
    final handle = win32.createPopupMenu();
    if (handle == ffi.nullptr) return null;
    return _WindowsTrayMenu(handle);
  }

  void addSeparator() {
    final win32 = WindowsTrayBindings.instance;
    if (win32 == null || hMenu == ffi.nullptr) return;
    win32.appendMenuW(hMenu, kMfSeparator, 0, ffi.nullptr);
  }

  void addItem(_WindowsTrayMenuItem item) {
    final win32 = WindowsTrayBindings.instance;
    if (win32 == null || hMenu == ffi.nullptr) return;
    itemsByCommandId[item.commandId] = item;
    item.parentMenu = hMenu;
    final flags = item.isEnabled ? kMfString : kMfDisabledFlags;
    TrayNativeMemory.withUtf16(
      item.label,
      (wstr) => win32.appendMenuW(hMenu, flags, item.commandId, wstr),
    );
  }

  void dispose() {
    itemsByCommandId.clear();
    if (hMenu == ffi.nullptr) return;
    WindowsTrayBindings.instance?.destroyMenu(hMenu);
  }
}

/// Returns whether the `LOWORD(lParam)` notification code of [kWmTrayIcon]
/// represents a primary tray icon selection (left mouse click release or
/// keyboard Space/Enter activation).
bool isWindowsTrayPrimarySelectEvent(int event) =>
    event == kWmLButtonUp || event == kNinSelect || event == kNinKeySelect;

/// Win32 (`Shell_NotifyIconW` + `MENUITEMINFOW` + Premultiplied BGRA DIB
/// `HBITMAP`) system tray backend for Windows 10 and Windows 11.
class WindowsTrayBackend<TIcon extends Enum> implements TrayBackend<TIcon> {
  /// Creates a [WindowsTrayBackend] with an optional [iconId] (`NOTIFYICONDATAW.uID`,
  /// defaults to `1`).
  WindowsTrayBackend({this.iconId = 1});

  static int _nextCommandId = 1000;

  /// Application-defined `NOTIFYICONDATAW.uID` identifier for this tray icon.
  final int iconId;

  ffi.Pointer<ffi.Void> _hostHwnd = ffi.nullptr;
  ffi.Pointer<ffi.Void> _trayHIcon = ffi.nullptr;
  int _taskbarCreatedMsg = 0;
  String _tooltip = '';

  _WindowsTrayMenu? _menu;
  final List<_WindowsTrayMenuItem> _items = <_WindowsTrayMenuItem>[];
  final List<TIcon?> _itemIcons = <TIcon?>[];
  final List<String?> _itemIds = <String?>[];
  final Map<TIcon, ffi.Pointer<ffi.Void>> _menuBitmaps =
      <TIcon, ffi.Pointer<ffi.Void>>{};
  String? _signature;
  void Function()? _onIconClicked;
  void Function(String id)? _onItemSelected;

  @override
  Future<bool> create({
    required String iconPath,
    required String tooltip,
    required void Function() onIconClicked,
    required void Function(String id) onItemSelected,
  }) async {
    dispose();

    final hIcon = loadWindowsTrayIconFromFile(iconPath);
    if (hIcon == ffi.nullptr) {
      throw ArgumentError('Tray icon could not be loaded: $iconPath');
    }
    _trayHIcon = hIcon;
    _tooltip = tooltip;
    _onIconClicked = onIconClicked;
    _onItemSelected = onItemSelected;

    final win32 = WindowsTrayBindings.instance;
    if (win32 == null) {
      dispose();
      return false;
    }

    TrayNativeMemory.withUtf16('TaskbarCreated', (msgPtr) {
      _taskbarCreatedMsg = win32.registerWindowMessageW(msgPtr);
    });

    final hwnd = win32.createHiddenHostWindow(_handleHostWindowMessage);
    if (hwnd == ffi.nullptr) {
      dispose();
      return false;
    }
    _hostHwnd = hwnd;

    final filterEx = win32.changeWindowMessageFilterEx;
    if (filterEx != null) {
      filterEx(hwnd, kWmTrayIcon, kMsgFltAllow, ffi.nullptr);
      if (_taskbarCreatedMsg != 0) {
        filterEx(hwnd, _taskbarCreatedMsg, kMsgFltAllow, ffi.nullptr);
      }
    }

    if (!_addNotifyIcon(win32, hwnd, hIcon, tooltip)) {
      dispose();
      return false;
    }
    return true;
  }

  bool _addNotifyIcon(
    WindowsTrayBindings win32,
    ffi.Pointer<ffi.Void> hwnd,
    ffi.Pointer<ffi.Void> hIcon,
    String tooltip,
  ) {
    if (hwnd == ffi.nullptr || hIcon == ffi.nullptr) return false;
    final nid = win32.scratchNid;
    final nidSize = ffi.sizeOf<Win32NotifyIconDataW>();
    TrayNativeMemory.zeroFill(nid.cast(), nidSize);
    nid.ref
      ..cbSize = nidSize
      ..hWnd = hwnd
      ..uID = iconId
      ..uFlags = kNifStandardFlags
      ..uCallbackMessage = kWmTrayIcon
      ..hIcon = hIcon;

    final sanitizedTip =
        tooltip.contains('\u0000') ? tooltip.replaceAll('\u0000', '') : tooltip;
    final tipUnits = sanitizedTip.codeUnits;
    var maxTip = tipUnits.length < 127 ? tipUnits.length : 127;
    if (maxTip > 0 &&
        maxTip < tipUnits.length &&
        (tipUnits[maxTip - 1] & 0xFC00) == 0xD800) {
      maxTip--;
    }
    for (var i = 0; i < maxTip; i++) {
      nid.ref.szTip[i] = tipUnits[i];
    }
    nid.ref.szTip[maxTip] = 0;

    return win32.shellNotifyIconW(kNimAdd, nid) != 0;
  }

  bool _handleHostWindowMessage(
    ffi.Pointer<ffi.Void> hwnd,
    int msg,
    int wParam,
    int lParam,
  ) {
    if (msg == kWmTrayIcon) {
      final event = lParam & 0xFFFF;
      if (isWindowsTrayPrimarySelectEvent(event)) {
        final win32 = WindowsTrayBindings.instance;
        if (win32 != null) {
          // Claim Win32 foreground ownership synchronously inside WM_TRAYICON
          // while explorer.exe's AllowSetForegroundWindow grant is active (the
          // same contract used by _showContextMenu) so subsequent window
          // restoration is never blocked by the Windows Foreground Lock.
          win32.setForegroundWindow(hwnd);
          win32.postMessageW(hwnd, kWmNull, 0, 0);
        }
        _onIconClicked?.call();
        return true;
      }
      if (event == kWmRButtonUp || event == kWmContextMenu) {
        _showContextMenu(hwnd);
        return true;
      }
      return false;
    }
    if (_taskbarCreatedMsg != 0 && msg == _taskbarCreatedMsg) {
      final win32 = WindowsTrayBindings.instance;
      if (win32 != null && _trayHIcon != ffi.nullptr) {
        _addNotifyIcon(win32, hwnd, _trayHIcon, _tooltip);
      }
      return true;
    }
    return false;
  }

  void _showContextMenu(ffi.Pointer<ffi.Void> hwnd) {
    final win32 = WindowsTrayBindings.instance;
    final menu = _menu;
    if (win32 == null || menu == null || menu.hMenu == ffi.nullptr) return;

    final pt = win32.scratchPoint;
    win32.getCursorPos(pt);
    win32.setForegroundWindow(hwnd);
    final cmd = win32.trackPopupMenu(
      menu.hMenu,
      kTpmTrayFlags,
      pt.ref.x,
      pt.ref.y,
      0,
      hwnd,
      ffi.nullptr,
    );
    // Required by Win32 `Shell_NotifyIcon` / `TrackPopupMenu` contract so the
    // popup menu dismisses cleanly and allows subsequent activation.
    win32.postMessageW(hwnd, kWmNull, 0, 0);
    if (cmd != 0) {
      menu.itemsByCommandId[cmd]?.invokeClick();
    }
  }

  @override
  void setMenuIcons(Map<TIcon, ResolvedTrayMenuIcon<TIcon>> icons) {
    final win32 = WindowsTrayBindings.instance;
    final previous = List<ffi.Pointer<ffi.Void>>.of(_menuBitmaps.values);
    _menuBitmaps.clear();

    for (final entry in icons.entries) {
      final hBitmap = createWindowsPremultipliedDibBitmap(
        filePath: entry.value.filePath,
        pngBytes: entry.value.pngBytes,
      );
      if (hBitmap != ffi.nullptr) {
        _menuBitmaps[entry.key] = hBitmap;
      }
    }

    for (var i = 0; i < _items.length && i < _itemIcons.length; i++) {
      final key = _itemIcons[i];
      if (key != null) {
        _items[i].bitmap = _menuBitmaps[key] ?? ffi.nullptr;
      }
    }

    if (win32 != null) {
      for (final old in previous) {
        if (old != ffi.nullptr) win32.deleteObject(old);
      }
    }
  }

  @override
  void setMenu(List<TrayMenuEntry<TIcon>> entries) {
    if (_hostHwnd == ffi.nullptr) return;

    final signature = trayMenuSignature(entries);
    if (_menu != null && signature == _signature) {
      var itemIndex = 0;
      for (final entry in entries) {
        if (entry is TrayMenuItemEntry<TIcon>) {
          final item = _items[itemIndex++];
          if (item.label != entry.label) item.label = entry.label;
          if (item.isEnabled != entry.enabled) item.isEnabled = entry.enabled;
        }
      }
      return;
    }

    final menu = _WindowsTrayMenu.create();
    if (menu == null) throw StateError('Tray menu could not be created.');
    final items = <_WindowsTrayMenuItem>[];
    final itemIcons = <TIcon?>[];
    final ids = <String?>[];

    populateNativeTrayMenuEntries<
      _WindowsTrayMenuItem,
      ffi.Pointer<ffi.Void>,
      TIcon
    >(
      entries: entries,
      menuImages: _menuBitmaps,
      addSeparator: menu.addSeparator,
      createItem:
          (label) =>
              _WindowsTrayMenuItem(commandId: _nextCommandId++, label: label),
      setEnabled: (item, enabled) => item.isEnabled = enabled,
      attachClickListener: (item, id) {
        item.setClickListener(() => _onItemSelected?.call(id));
      },
      addItemToMenu: menu.addItem,
      setItemIcon: (item, hBitmap) => item.bitmap = hBitmap,
      outItems: items,
      outItemIcons: itemIcons,
      outIds: ids,
    );

    final oldMenu = _menu;
    _menu = menu;
    _items
      ..clear()
      ..addAll(items);
    _itemIcons
      ..clear()
      ..addAll(itemIcons);
    _itemIds
      ..clear()
      ..addAll(ids);
    _signature = signature;

    oldMenu?.dispose();
  }

  @override
  void dispose() {
    final win32 = WindowsTrayBindings.instance;
    final hwnd = _hostHwnd;
    final hIcon = _trayHIcon;
    final menu = _menu;
    final bitmaps = List<ffi.Pointer<ffi.Void>>.of(_menuBitmaps.values);

    _hostHwnd = ffi.nullptr;
    _trayHIcon = ffi.nullptr;
    _menu = null;
    _items.clear();
    _itemIcons.clear();
    _itemIds.clear();
    _menuBitmaps.clear();
    _signature = null;
    _onIconClicked = null;
    _onItemSelected = null;

    if (win32 != null) {
      if (hwnd != ffi.nullptr) {
        final nid = win32.scratchNid;
        final nidSize = ffi.sizeOf<Win32NotifyIconDataW>();
        TrayNativeMemory.zeroFill(nid.cast(), nidSize);
        nid.ref
          ..cbSize = nidSize
          ..hWnd = hwnd
          ..uID = iconId;
        win32.shellNotifyIconW(kNimDelete, nid);
        win32.destroyHiddenHostWindow(hwnd);
      }
      menu?.dispose();
      for (final bmp in bitmaps) {
        if (bmp != ffi.nullptr) win32.deleteObject(bmp);
      }
      if (hIcon != ffi.nullptr) {
        win32.destroyIcon(hIcon);
      }
    }
  }
}

/// Symmetric platform alias for [WindowsTrayBackend].
typedef WindowsWin32TrayBackend<TIcon extends Enum> = WindowsTrayBackend<TIcon>;
