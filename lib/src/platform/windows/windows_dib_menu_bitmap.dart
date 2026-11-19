import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../ffi/tray_native_memory.dart';
import 'windows_notify_icon_abi.dart';

/// Loads a `.ico` tray icon from [filePath] via Win32 `LoadImageW`.
ffi.Pointer<ffi.Void> loadWindowsTrayIconFromFile(String filePath) {
  final win32 = WindowsTrayBindings.instance;
  if (win32 == null || !File(filePath).existsSync()) return ffi.nullptr;
  try {
    return TrayNativeMemory.withUtf16(
      filePath,
      (wstr) => win32.loadImageW(
        ffi.nullptr,
        wstr,
        kImageIcon,
        0,
        0,
        kLrLoadFileDefaultSize,
      ),
    );
  } catch (_) {
    return ffi.nullptr;
  }
}

/// Decodes [pngBytes] into a 32-bit top-down Premultiplied BGRA Win32 DIB
/// `HBITMAP` suitable for `MENUITEMINFOW.hbmpItem` (`AlphaBlend`).
ffi.Pointer<ffi.Void> createWindowsPremultipliedDibBitmapFromBytes(
  Uint8List pngBytes,
) {
  final win32 = WindowsTrayBindings.instance;
  if (win32 == null || pngBytes.isEmpty) return ffi.nullptr;

  final decoded = img.decodePng(pngBytes);
  if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
    return ffi.nullptr;
  }

  final width = decoded.width;
  final height = decoded.height;
  final bmi =
      TrayNativeMemory.malloc(
        ffi.sizeOf<Win32BitmapInfoHeader>(),
      ).cast<Win32BitmapInfoHeader>();
  final bitsOut =
      TrayNativeMemory.malloc(
        ffi.sizeOf<ffi.Pointer<ffi.Uint8>>(),
      ).cast<ffi.Pointer<ffi.Uint8>>();
  if (bmi == ffi.nullptr || bitsOut == ffi.nullptr) {
    if (bmi != ffi.nullptr) TrayNativeMemory.free(bmi.cast());
    if (bitsOut != ffi.nullptr) TrayNativeMemory.free(bitsOut.cast());
    return ffi.nullptr;
  }

  try {
    TrayNativeMemory.zeroFill(bmi.cast(), ffi.sizeOf<Win32BitmapInfoHeader>());
    bmi.ref
      ..biSize = ffi.sizeOf<Win32BitmapInfoHeader>()
      ..biWidth = width
      ..biHeight =
          -height // top-down DIB
      ..biPlanes = 1
      ..biBitCount = 32
      ..biCompression =
          0 // BI_RGB
      ..biSizeImage = width * height * 4;

    bitsOut.value = ffi.nullptr;
    final hBitmap = win32.createDIBSection(
      ffi.nullptr,
      bmi,
      0,
      bitsOut,
      ffi.nullptr,
      0,
    );
    if (hBitmap == ffi.nullptr || bitsOut.value == ffi.nullptr) {
      if (hBitmap != ffi.nullptr) win32.deleteObject(hBitmap);
      return ffi.nullptr;
    }

    final dst = bitsOut.value;
    var offset = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final p = decoded.getPixel(x, y);
        final a = p.a.toInt().clamp(0, 255);
        // Premultiplied BGRA required by Win32 AlphaBlend / MENUITEMINFO
        final r = ((p.r.toInt() * a) ~/ 255).clamp(0, 255);
        final g = ((p.g.toInt() * a) ~/ 255).clamp(0, 255);
        final b = ((p.b.toInt() * a) ~/ 255).clamp(0, 255);
        dst[offset++] = b;
        dst[offset++] = g;
        dst[offset++] = r;
        dst[offset++] = a;
      }
    }
    return hBitmap;
  } finally {
    TrayNativeMemory.free(bmi.cast());
    TrayNativeMemory.free(bitsOut.cast());
  }
}

/// Loads [filePath] (or falls back to [pngBytes]) into a 32-bit Premultiplied
/// BGRA Win32 DIB `HBITMAP`.
ffi.Pointer<ffi.Void> createWindowsPremultipliedDibBitmap({
  required String filePath,
  Uint8List? pngBytes,
}) {
  try {
    if (pngBytes != null && pngBytes.isNotEmpty) {
      final fromMem = createWindowsPremultipliedDibBitmapFromBytes(pngBytes);
      if (fromMem != ffi.nullptr) return fromMem;
    }
    if (File(filePath).existsSync()) {
      return createWindowsPremultipliedDibBitmapFromBytes(
        File(filePath).readAsBytesSync(),
      );
    }
  } catch (_) {
    // Return nullptr on malformed PNG input.
  }
  return ffi.nullptr;
}

/// Snapshot returned by [debugCreateWindowsMenuDibRoundTrip] verifying live
/// GDI `CreateDIBSection` + `GetObjectW` Premultiplied BGRA output on Windows.
class WindowsDibProbeResult {
  /// Creates a [WindowsDibProbeResult].
  const WindowsDibProbeResult({
    required this.width,
    required this.height,
    required this.bitsPerPixel,
    required this.firstPixelB,
    required this.firstPixelG,
    required this.firstPixelR,
    required this.firstPixelA,
    required this.deletedCleanly,
  });

  /// Reported `BITMAP.bmWidth`.
  final int width;

  /// Reported `BITMAP.bmHeight`.
  final int height;

  /// Reported `BITMAP.bmBitsPixel`.
  final int bitsPerPixel;

  /// Premultiplied Blue channel of pixel `(0, 0)`.
  final int firstPixelB;

  /// Premultiplied Green channel of pixel `(0, 0)`.
  final int firstPixelG;

  /// Premultiplied Red channel of pixel `(0, 0)`.
  final int firstPixelR;

  /// Alpha channel of pixel `(0, 0)`.
  final int firstPixelA;

  /// Whether `DeleteObject(hBitmap)` succeeded (`!= 0`).
  final bool deletedCleanly;
}

/// Synthesizes a `32×32` semi-transparent RGBA PNG in memory, creates a real
/// Win32 `HBITMAP` via [createWindowsPremultipliedDibBitmapFromBytes], inspects
/// it via `GetObjectW`, and frees it via `DeleteObject`.
///
/// Returns `null` on non-Windows platforms.
WindowsDibProbeResult? debugCreateWindowsMenuDibRoundTrip() {
  if (!Platform.isWindows) return null;
  final win32 = WindowsTrayBindings.instance;
  if (win32 == null) return null;

  final canvas = img.Image(width: 32, height: 32, numChannels: 4);
  // R=200, G=100, B=50, A=128 -> premultiplied R=100, G=50, B=25, A=128
  canvas.setPixelRgba(0, 0, 200, 100, 50, 128);
  final png = Uint8List.fromList(img.encodePng(canvas));

  final hBitmap = createWindowsPremultipliedDibBitmapFromBytes(png);
  if (hBitmap == ffi.nullptr) return null;

  final bmpSize = ffi.sizeOf<Win32Bitmap>();
  final bmp = TrayNativeMemory.malloc(bmpSize).cast<Win32Bitmap>();
  try {
    TrayNativeMemory.zeroFill(bmp.cast(), bmpSize);
    final got = win32.getObjectW(hBitmap, bmpSize, bmp.cast());
    if (got == 0 || bmp.ref.bmBits == ffi.nullptr) {
      win32.deleteObject(hBitmap);
      return null;
    }
    final bits = bmp.ref.bmBits;
    final b = bits[0];
    final g = bits[1];
    final r = bits[2];
    final a = bits[3];
    final w = bmp.ref.bmWidth;
    final h = bmp.ref.bmHeight.abs();
    final bpp = bmp.ref.bmBitsPixel;
    final deleted = win32.deleteObject(hBitmap) != 0;
    return WindowsDibProbeResult(
      width: w,
      height: h,
      bitsPerPixel: bpp,
      firstPixelB: b,
      firstPixelG: g,
      firstPixelR: r,
      firstPixelA: a,
      deletedCleanly: deleted,
    );
  } finally {
    TrayNativeMemory.free(bmp.cast());
  }
}
