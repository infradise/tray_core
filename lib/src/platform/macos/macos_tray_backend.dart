import 'dart:ffi' as ffi;
import 'dart:io';

import '../../tray_backend.dart';
import '../../tray_menu_entry.dart';
import 'macos_menu_visibility.dart';
import 'macos_objc_bindings.dart';

class _MacOSTrayImage {
  _MacOSTrayImage(this.nativeObject);

  final ffi.Pointer<ffi.Void> nativeObject;

  static _MacOSTrayImage? fromFile(String filePath, {required bool forMenu}) {
    if (!File(filePath).existsSync()) return null;
    final objc = MacOSTrayObjCBindings.instance;
    if (objc == null) return null;

    try {
      final nsPath = objc.nsString(filePath);
      if (nsPath == ffi.nullptr) return null;

      final nsImageClass = objc.getClass('NSImage');
      if (nsImageClass == ffi.nullptr) return null;

      final allocated = objc.sendId(nsImageClass, objc.sel('alloc'));
      final image = objc.sendId1(
        allocated,
        objc.sel('initWithContentsOfFile:'),
        nsPath,
      );
      if (image == ffi.nullptr) return null;

      final edge = forMenu ? 16.0 : 18.0;
      objc.sendVoidSize(image, objc.sel('setSize:'), edge, edge);
      objc.sendVoidBool(image, objc.sel('setTemplate:'), true);
      return _MacOSTrayImage(image);
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    if (nativeObject == ffi.nullptr) return;
    try {
      final objc = MacOSTrayObjCBindings.instance;
      objc?.sendVoid(nativeObject, objc.sel('release'));
    } catch (_) {
      // Ignore release failure during process shutdown.
    }
  }
}

class _MacOSTrayMenuItem {
  _MacOSTrayMenuItem({
    required this.commandId,
    required String label,
    required this.nativeObject,
  }) : _label = label;

  final int commandId;
  final ffi.Pointer<ffi.Void> nativeObject;

  String _label;
  bool _isEnabled = true;
  _MacOSTrayImage? _icon;

  String get label => _label;

  set label(String value) {
    _label = value;
    if (nativeObject == ffi.nullptr) return;
    final objc = MacOSTrayObjCBindings.instance;
    if (objc == null) return;
    final nsTitle = objc.nsString(value);
    if (nsTitle != ffi.nullptr) {
      objc.sendVoidId(nativeObject, objc.sel('setTitle:'), nsTitle);
    }
  }

  bool get isEnabled => _isEnabled;

  set isEnabled(bool value) {
    _isEnabled = value;
    if (nativeObject == ffi.nullptr) return;
    final objc = MacOSTrayObjCBindings.instance;
    objc?.sendVoidBool(nativeObject, objc.sel('setEnabled:'), value);
  }

  _MacOSTrayImage? get icon => _icon;

  set icon(_MacOSTrayImage? value) {
    _icon = value;
    if (nativeObject == ffi.nullptr) return;
    final objc = MacOSTrayObjCBindings.instance;
    objc?.sendVoidId(
      nativeObject,
      objc.sel('setImage:'),
      value?.nativeObject ?? ffi.nullptr,
    );
  }

  void dispose() {
    final objc = MacOSTrayObjCBindings.instance;
    objc?.unregisterMenuAction(commandId);
    if (nativeObject == ffi.nullptr) return;
    try {
      objc?.sendVoid(nativeObject, objc.sel('release'));
    } catch (_) {
      // Ignore release failure during process shutdown.
    }
  }
}

class _MacOSTrayMenu {
  _MacOSTrayMenu(this.nativeObject);

  final ffi.Pointer<ffi.Void> nativeObject;

  static _MacOSTrayMenu? create() {
    final objc = MacOSTrayObjCBindings.instance;
    if (objc == null) return null;
    try {
      final nsMenuClass = objc.getClass('NSMenu');
      if (nsMenuClass == ffi.nullptr) return null;
      final menu = objc.sendId(
        objc.sendId(nsMenuClass, objc.sel('alloc')),
        objc.sel('init'),
      );
      if (menu == ffi.nullptr) return null;
      objc.sendVoidBool(menu, objc.sel('setAutoenablesItems:'), false);
      return _MacOSTrayMenu(menu);
    } catch (_) {
      return null;
    }
  }

  void addSeparator() {
    if (nativeObject == ffi.nullptr) return;
    final objc = MacOSTrayObjCBindings.instance;
    if (objc == null) return;
    try {
      final nsMenuItemClass = objc.getClass('NSMenuItem');
      final sep = objc.sendId(nsMenuItemClass, objc.sel('separatorItem'));
      objc.sendVoidId(nativeObject, objc.sel('addItem:'), sep);
    } catch (_) {
      // Ignore separator insertion failure.
    }
  }

  void addItem(_MacOSTrayMenuItem item) {
    if (nativeObject == ffi.nullptr || item.nativeObject == ffi.nullptr) return;
    final objc = MacOSTrayObjCBindings.instance;
    if (objc == null) return;
    try {
      objc.sendVoidId(nativeObject, objc.sel('addItem:'), item.nativeObject);
    } catch (_) {
      // Ignore menu item insertion failure.
    }
  }

  void dispose() {
    if (nativeObject == ffi.nullptr) return;
    try {
      final objc = MacOSTrayObjCBindings.instance;
      objc?.sendVoid(nativeObject, objc.sel('release'));
    } catch (_) {
      // Ignore release failure during shutdown.
    }
  }
}

/// AppKit (`NSStatusBar` / `NSStatusItem` / `NSMenu`) system tray backend for
/// macOS 13 Ventura through macOS 27+.
class MacOSTrayBackend<TIcon extends Enum> implements TrayBackend<TIcon> {
  /// Creates a [MacOSTrayBackend].
  MacOSTrayBackend();

  static int _nextCommandId = 1000;

  ffi.Pointer<ffi.Void> _statusItem = ffi.nullptr;
  _MacOSTrayImage? _trayIconImage;
  _MacOSTrayMenu? _menu;
  final List<_MacOSTrayMenuItem> _items = <_MacOSTrayMenuItem>[];
  final List<TIcon?> _itemIcons = <TIcon?>[];
  final List<String?> _itemIds = <String?>[];
  final Map<TIcon, _MacOSTrayImage> _menuImages = <TIcon, _MacOSTrayImage>{};
  String? _signature;
  void Function(String id)? _onItemSelected;

  @override
  Future<bool> create({
    required String iconPath,
    required String tooltip,
    required void Function() onIconClicked,
    required void Function(String id) onItemSelected,
  }) async {
    dispose();
    _onItemSelected = onItemSelected;

    final image = _MacOSTrayImage.fromFile(iconPath, forMenu: false);
    if (image == null) {
      throw ArgumentError('Tray icon could not be loaded: $iconPath');
    }
    _trayIconImage = image;

    final objc = MacOSTrayObjCBindings.instance;
    if (objc == null) {
      dispose();
      return false;
    }

    try {
      final statusBarClass = objc.getClass('NSStatusBar');
      if (statusBarClass == ffi.nullptr) {
        dispose();
        return false;
      }
      final systemBar = objc.sendId(
        statusBarClass,
        objc.sel('systemStatusBar'),
      );
      if (systemBar == ffi.nullptr) {
        dispose();
        return false;
      }

      // NSVariableStatusItemLength = -1.0
      final statusItem = objc.sendIdDouble(
        systemBar,
        objc.sel('statusItemWithLength:'),
        -1.0,
      );
      if (statusItem == ffi.nullptr) {
        dispose();
        return false;
      }
      objc.sendVoid(statusItem, objc.sel('retain'));
      _statusItem = statusItem;

      final button = objc.sendId(statusItem, objc.sel('button'));
      if (button != ffi.nullptr) {
        objc.sendVoidId(button, objc.sel('setImage:'), image.nativeObject);
        final nsTip = objc.nsString(tooltip);
        if (nsTip != ffi.nullptr) {
          objc.sendVoidId(button, objc.sel('setToolTip:'), nsTip);
        }
      }
      return true;
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  @override
  void setMenuIcons(Map<TIcon, ResolvedTrayMenuIcon<TIcon>> icons) {
    final previous = List<_MacOSTrayImage>.of(_menuImages.values);
    _menuImages.clear();

    for (final entry in icons.entries) {
      final img = _MacOSTrayImage.fromFile(entry.value.filePath, forMenu: true);
      if (img != null) {
        _menuImages[entry.key] = img;
      }
    }

    for (var i = 0; i < _items.length && i < _itemIcons.length; i++) {
      final key = _itemIcons[i];
      if (key != null) {
        _applyItemIcon(_items[i], _menuImages[key]);
      }
    }

    for (final old in previous) {
      old.dispose();
    }
  }

  @override
  void setMenu(List<TrayMenuEntry<TIcon>> entries) {
    if (_statusItem == ffi.nullptr) return;

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

    final menu = _MacOSTrayMenu.create();
    if (menu == null) throw StateError('Tray menu could not be created.');
    final items = <_MacOSTrayMenuItem>[];
    final itemIcons = <TIcon?>[];
    final ids = <String?>[];

    populateNativeTrayMenuEntries<_MacOSTrayMenuItem, _MacOSTrayImage, TIcon>(
      entries: entries,
      menuImages: _menuImages,
      addSeparator: menu.addSeparator,
      createItem: _createMenuItem,
      setEnabled: (item, enabled) => item.isEnabled = enabled,
      attachClickListener: (item, id) {
        MacOSTrayObjCBindings.instance?.registerMenuAction(
          item.commandId,
          () => _onItemSelected?.call(id),
        );
      },
      addItemToMenu: menu.addItem,
      setItemIcon: _applyItemIcon,
      outItems: items,
      outItemIcons: itemIcons,
      outIds: ids,
    );

    final objc = MacOSTrayObjCBindings.instance;
    objc?.sendVoidId(_statusItem, objc.sel('setMenu:'), menu.nativeObject);

    final oldMenu = _menu;
    final oldItems = List<_MacOSTrayMenuItem>.of(_items);
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

    for (final item in oldItems) {
      item.dispose();
    }
    oldMenu?.dispose();
  }

  static _MacOSTrayMenuItem? _createMenuItem(String label) {
    final objc = MacOSTrayObjCBindings.instance;
    if (objc == null) return null;
    final nsMenuItemClass = objc.getClass('NSMenuItem');
    if (nsMenuItemClass == ffi.nullptr) return null;
    final nsTitle = objc.nsString(label);
    final nsKeyEq = objc.nsString('');
    if (nsTitle == ffi.nullptr || nsKeyEq == ffi.nullptr) return null;
    final allocated = objc.sendId(nsMenuItemClass, objc.sel('alloc'));
    if (allocated == ffi.nullptr) return null;

    final nsItem = objc.sendIdInitItem(
      allocated,
      objc.sel('initWithTitle:action:keyEquivalent:'),
      nsTitle,
      objc.sel('onTrayMenuItemClicked:'),
      nsKeyEq,
    );
    if (nsItem == ffi.nullptr) return null;

    final commandId = _nextCommandId++;
    final target = objc.ensureMenuTarget();
    objc.sendVoidId(nsItem, objc.sel('setTarget:'), target);
    objc.sendVoidInt(nsItem, objc.sel('setTag:'), commandId);

    return _MacOSTrayMenuItem(
      commandId: commandId,
      label: label,
      nativeObject: nsItem,
    );
  }

  static void _applyItemIcon(_MacOSTrayMenuItem item, _MacOSTrayImage? image) {
    item.icon = image;
    setMacOSMenuItemImageVisibility(item.nativeObject, visible: image != null);
  }

  @override
  void dispose() {
    final menu = _menu;
    final items = List<_MacOSTrayMenuItem>.of(_items);
    final menuImages = List<_MacOSTrayImage>.of(_menuImages.values);
    final trayIconImage = _trayIconImage;
    _menu = null;
    _trayIconImage = null;
    _items.clear();
    _itemIcons.clear();
    _itemIds.clear();
    _menuImages.clear();
    _signature = null;
    _onItemSelected = null;

    if (_statusItem != ffi.nullptr) {
      final statusItem = _statusItem;
      _statusItem = ffi.nullptr;
      try {
        final objc = MacOSTrayObjCBindings.instance;
        if (objc != null) {
          final statusBarClass = objc.getClass('NSStatusBar');
          final systemBar = objc.sendId(
            statusBarClass,
            objc.sel('systemStatusBar'),
          );
          objc.sendVoidId(systemBar, objc.sel('removeStatusItem:'), statusItem);
          objc.sendVoid(statusItem, objc.sel('release'));
        }
      } catch (_) {
        // Ignore status bar removal failure on exit.
      }
    }

    for (final item in items) {
      item.dispose();
    }
    for (final image in menuImages) {
      image.dispose();
    }
    menu?.dispose();
    trayIconImage?.dispose();
  }
}

/// Symmetric platform alias for [MacOSTrayBackend].
typedef MacOSStatusItemTrayBackend<TIcon extends Enum> =
    MacOSTrayBackend<TIcon>;

/// Instantiates a real AppKit `NSMenuItem` on macOS, optionally updates its
/// title via `setTitle:`, reads back `[nsItem title].UTF8String`, and releases
/// the item. Returns `null` on non-macOS platforms.
String? debugCreateMacOSMenuItemTitleRoundTrip(
  String initialLabel, {
  String? updatedLabel,
}) {
  if (!Platform.isMacOS) return null;
  final item = MacOSTrayBackend._createMenuItem(initialLabel);
  if (item == null) return null;
  try {
    if (updatedLabel != null) {
      item.label = updatedLabel;
    }
    final objc = MacOSTrayObjCBindings.instance;
    if (objc == null) return null;
    final nsTitle = objc.sendId(item.nativeObject, objc.sel('title'));
    return objc.dartStringFromNSString(nsTitle);
  } finally {
    item.dispose();
  }
}
