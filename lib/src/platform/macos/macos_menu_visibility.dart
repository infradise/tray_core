import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'macos_objc_bindings.dart';

/// `NSMenuItemImageVisibilityAutomatic` (`0`, macOS 27.0+).
const int kNSMenuItemImageVisibilityAutomatic = 0;

/// `NSMenuItemImageVisibilityVisible` (`1`, macOS 27.0+).
const int kNSMenuItemImageVisibilityVisible = 1;

/// `NSMenuItemImageVisibilityHidden` (`2`, macOS 27.0+).
const int kNSMenuItemImageVisibilityHidden = 2;

/// Ensures `NSMenuItem.image` is visible on macOS 27+ by setting
/// `NSMenuItem.preferredImageVisibility` to `.visible` (`1`) when [visible] is
/// `true` (or `.automatic` (`0`) when `false`), and notifies
/// `[parentMenu itemChanged:]`.
///
/// Safely returns `false` (no-op) on macOS 13 Ventura through macOS 26 Tahoe
/// and on non-macOS platforms.
bool setMacOSMenuItemImageVisibility(
  Pointer<Void> nsMenuItem, {
  required bool visible,
}) {
  if (!Platform.isMacOS || nsMenuItem == nullptr) return false;
  final objc = MacOSTrayObjCBindings.instance;
  if (objc == null) return false;

  try {
    final cls = objc.objectGetClass(nsMenuItem);
    if (cls == nullptr) return false;
    final selSetVis = objc.sel('setPreferredImageVisibility:');
    if (objc.classGetInstanceMethod(cls, selSetVis) == nullptr) {
      return false;
    }

    final targetVisibility =
        visible
            ? kNSMenuItemImageVisibilityVisible
            : kNSMenuItemImageVisibilityAutomatic;
    objc.sendVoidInt(nsMenuItem, selSetVis, targetVisibility);

    final parentMenu = objc.sendId(nsMenuItem, objc.sel('menu'));
    if (parentMenu != nullptr) {
      final menuCls = objc.objectGetClass(parentMenu);
      final selChanged = objc.sel('itemChanged:');
      if (menuCls != nullptr &&
          objc.classGetInstanceMethod(menuCls, selChanged) != nullptr) {
        objc.sendVoidId(parentMenu, selChanged, nsMenuItem);
      }
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Reads `NSMenuItem.preferredImageVisibility` on macOS 27+, or returns `null`
/// on non-macOS platforms or macOS 13–26 builds without that property.
@visibleForTesting
int? getMacOSMenuItemImageVisibility(Pointer<Void> nsMenuItem) {
  if (!Platform.isMacOS || nsMenuItem == nullptr) return null;
  final objc = MacOSTrayObjCBindings.instance;
  if (objc == null) return null;

  try {
    final cls = objc.objectGetClass(nsMenuItem);
    if (cls == nullptr) return null;
    final selGetVis = objc.sel('preferredImageVisibility');
    if (objc.classGetInstanceMethod(cls, selGetVis) == nullptr) {
      return null;
    }
    return objc.sendInt(nsMenuItem, selGetVis);
  } catch (_) {
    return null;
  }
}
