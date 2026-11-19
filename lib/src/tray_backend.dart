import 'dart:io';

import 'platform/linux/linux_sni_tray_backend.dart';
import 'platform/macos/macos_tray_backend.dart';
import 'platform/windows/windows_tray_backend.dart';
import 'tray_menu_entry.dart';

/// Unified desktop system tray contract backed by `StatusNotifierItem` +
/// `com.canonical.dbusmenu` on Linux, `NSStatusItem` + `NSMenu` on macOS, and
/// `Shell_NotifyIconW` + Premultiplied BGRA DIB `HBITMAP` menus on Windows.
abstract class TrayBackend<TIcon extends Enum> {
  /// Default generative constructor for subclasses.
  const TrayBackend();

  /// Returns the platform-appropriate [TrayBackend] for the current desktop OS
  /// (`LinuxDbusTrayBackend` on Linux, `MacOSTrayBackend` on macOS,
  /// `WindowsTrayBackend` on Windows).
  factory TrayBackend.forCurrentPlatform({
    String? applicationId,
    int windowsIconId = 1,
  }) {
    if (Platform.isLinux) {
      return LinuxDbusTrayBackend<TIcon>(applicationId: applicationId);
    }
    if (Platform.isMacOS) {
      return MacOSTrayBackend<TIcon>();
    }
    if (Platform.isWindows) {
      return WindowsTrayBackend<TIcon>(iconId: windowsIconId);
    }
    return _UnsupportedTrayBackend<TIcon>();
  }

  /// Creates and shows the tray icon. Returns `false` when the OS refuses or
  /// lacks a system tray host.
  ///
  /// [onIconClicked] fires on primary icon click on Windows and Linux; on
  /// macOS, primary click opens the attached `NSMenu` directly in accordance
  /// with macOS menu bar conventions.
  Future<bool> create({
    required String iconPath,
    required String tooltip,
    required void Function() onIconClicked,
    required void Function(String id) onItemSelected,
  });

  /// Supplies rasterized PNG icons keyed by [TIcon] for context menu entries.
  void setMenuIcons(Map<TIcon, ResolvedTrayMenuIcon<TIcon>> icons) {}

  /// Replaces or updates the context menu in place.
  void setMenu(List<TrayMenuEntry<TIcon>> entries);

  /// Releases all native resources. Safe to call more than once.
  void dispose();
}

class _UnsupportedTrayBackend<TIcon extends Enum> extends TrayBackend<TIcon> {
  @override
  Future<bool> create({
    required String iconPath,
    required String tooltip,
    required void Function() onIconClicked,
    required void Function(String id) onItemSelected,
  }) async => false;

  @override
  void setMenu(List<TrayMenuEntry<TIcon>> entries) {}

  @override
  void dispose() {}
}
