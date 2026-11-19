import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:tray_core/src/testing/tray_core_testing.dart';

void main() {
  group('Windows Win32 NOTIFYICONDATAW ABI and Premultiplied BGRA DIB HBITMAP', () {
    test(
      'debugWin32NotifyIconDataWSize matches official Win32 sizeof(NOTIFYICONDATAW) ABI',
      () {
        final expected = sizeOf<Pointer<Void>>() == 8 ? 976 : 956;
        expect(debugWin32NotifyIconDataWSize, equals(expected));
      },
    );

    test(
      'CreateDIBSection builds live 32x32 Premultiplied BGRA HBITMAP verified by GetObjectW and frees cleanly on Windows',
      () {
        if (!Platform.isWindows) return;
        final probe = debugCreateWindowsMenuDibRoundTrip();
        expect(probe, isNotNull);
        expect(probe!.width, equals(32));
        expect(probe.height, equals(32));
        expect(probe.bitsPerPixel, equals(32));
        // Input RGBA(200, 100, 50, 128) -> Premultiplied BGRA:
        // B = (50 * 128) ~/ 255 = 25, G = (100 * 128) ~/ 255 = 50,
        // R = (200 * 128) ~/ 255 = 100, A = 128
        expect(probe.firstPixelB, equals(25));
        expect(probe.firstPixelG, equals(50));
        expect(probe.firstPixelR, equals(100));
        expect(probe.firstPixelA, equals(128));
        expect(probe.deletedCleanly, isTrue);
      },
    );

    test(
      'isWindowsTrayPrimarySelectEvent matches left-click release and NIN_SELECT / NIN_KEYSELECT only',
      () {
        expect(isWindowsTrayPrimarySelectEvent(kWmLButtonUp), isTrue);
        expect(isWindowsTrayPrimarySelectEvent(kNinSelect), isTrue);
        expect(isWindowsTrayPrimarySelectEvent(kNinKeySelect), isTrue);
        expect(isWindowsTrayPrimarySelectEvent(0x0201), isFalse); // LBUTTONDOWN
        expect(isWindowsTrayPrimarySelectEvent(0x0200), isFalse); // MOUSEMOVE
        expect(isWindowsTrayPrimarySelectEvent(kWmRButtonUp), isFalse);
      },
    );
  });
}
