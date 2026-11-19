import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Default Flutter asset path for `.png` tray icons (macOS & Linux).
const String kTrayIconPngAsset = 'resources/images/tray/tray_icon.png';

/// Default Flutter asset path for `.ico` tray icons (Windows).
const String kTrayIconIcoAsset = 'resources/images/tray/tray_icon.ico';

/// Selects `.ico` on Windows (`[isWindows] == true`) and `.png` otherwise.
String trayIconAssetFor({
  required bool isWindows,
  String pngAsset = kTrayIconPngAsset,
  String icoAsset = kTrayIconIcoAsset,
}) => isWindows ? icoAsset : pngAsset;

/// Extracts a bundled Flutter tray icon asset to a temporary file atomically
/// (`*.pid.tmp` -> `rename`) so OS tray APIs requiring a filesystem path can
/// load it reliably.
class TrayIconResolver {
  /// Creates a [TrayIconResolver].
  TrayIconResolver({
    AssetBundle? bundle,
    this.tempRoot,
    this.tempSubdir = 'tray_core_icons',
    this.pngAsset = kTrayIconPngAsset,
    this.icoAsset = kTrayIconIcoAsset,
  }) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  /// Optional explicit directory into which extracted icon files are written.
  final Directory? tempRoot;

  /// Subdirectory name under `Directory.systemTemp` used when [tempRoot] is
  /// omitted.
  final String tempSubdir;

  /// Asset key used on macOS and Linux.
  final String pngAsset;

  /// Asset key used on Windows.
  final String icoAsset;

  /// Extracts the platform-appropriate icon asset to disk and returns its
  /// absolute file path.
  Future<String> resolve({required bool isWindows}) async {
    final asset = trayIconAssetFor(
      isWindows: isWindows,
      pngAsset: pngAsset,
      icoAsset: icoAsset,
    );
    final data = await _bundle.load(asset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );

    final root =
        tempRoot ?? Directory(p.join(Directory.systemTemp.path, tempSubdir));
    await root.create(recursive: true);

    final file = File(p.join(root.path, p.basename(asset)));
    final partial = File('${file.path}.$pid.tmp');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(file.path);
    return file.path;
  }
}
