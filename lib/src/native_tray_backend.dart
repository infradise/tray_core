import 'dart:io';

import 'platform/macos/macos_tray_backend.dart';
import 'platform/windows/windows_tray_backend.dart';
import 'tray_backend.dart';
import 'tray_menu_entry.dart';

/// Cross-platform native FFI [TrayBackend] delegating to [MacOSTrayBackend] on
/// macOS and [WindowsTrayBackend] on Windows.
///
/// For automatic 3-platform dispatch including Linux `StatusNotifierItem`,
/// prefer [TrayBackend.forCurrentPlatform].
class NativeTrayBackend<TIcon extends Enum> implements TrayBackend<TIcon> {
  /// Creates a [NativeTrayBackend] for the active native OS.
  NativeTrayBackend({int windowsIconId = 1})
    : _delegate = _createDelegate(windowsIconId: windowsIconId);

  final TrayBackend<TIcon>? _delegate;

  static TrayBackend<TIcon>? _createDelegate<TIcon extends Enum>({
    required int windowsIconId,
  }) {
    if (Platform.isMacOS) return MacOSTrayBackend<TIcon>();
    if (Platform.isWindows) {
      return WindowsTrayBackend<TIcon>(iconId: windowsIconId);
    }
    return null;
  }

  @override
  Future<bool> create({
    required String iconPath,
    required String tooltip,
    required void Function() onIconClicked,
    required void Function(String id) onItemSelected,
  }) async {
    final delegate = _delegate;
    if (delegate == null) {
      if (!File(iconPath).existsSync()) {
        throw ArgumentError('Tray icon could not be loaded: $iconPath');
      }
      return false;
    }
    return delegate.create(
      iconPath: iconPath,
      tooltip: tooltip,
      onIconClicked: onIconClicked,
      onItemSelected: onItemSelected,
    );
  }

  @override
  void setMenuIcons(Map<TIcon, ResolvedTrayMenuIcon<TIcon>> icons) {
    _delegate?.setMenuIcons(icons);
  }

  @override
  void setMenu(List<TrayMenuEntry<TIcon>> entries) {
    _delegate?.setMenu(entries);
  }

  @override
  void dispose() {
    _delegate?.dispose();
  }
}
