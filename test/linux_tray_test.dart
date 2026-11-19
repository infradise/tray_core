import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tray_core/tray_core.dart';

enum _DemoIcon { open, quit }

void main() {
  group('Linux StatusNotifierItem, DBusMenu, and session environment', () {
    test('DbusMenuStateMachine updates in-place when signature matches', () {
      final sm =
          DbusMenuStateMachine<_DemoIcon>()..setIcons(<_DemoIcon, Uint8List>{
            _DemoIcon.open: Uint8List.fromList(const <int>[1, 2, 3]),
            _DemoIcon.quit: Uint8List.fromList(const <int>[4, 5, 6]),
          });

      final first = sm.updateEntries(const <TrayMenuEntry<_DemoIcon>>[
        TrayMenuItemEntry(id: 'open', label: 'Open (1)', icon: _DemoIcon.open),
      ]);
      expect(first.layoutChanged, isTrue);

      final second = sm.updateEntries(const <TrayMenuEntry<_DemoIcon>>[
        TrayMenuItemEntry(id: 'open', label: 'Open (2)', icon: _DemoIcon.open),
      ]);
      expect(second.layoutChanged, isFalse);
      expect(second.updatedProperties, hasLength(1));
    });

    test(
      'decodePngToSniIconPixmap converts RGBA PNG into ARGB32 big-endian SNI pixmap',
      () {
        final canvas = img.Image(width: 2, height: 2, numChannels: 4)
          ..setPixelRgba(0, 0, 10, 20, 30, 255);
        final pngBytes = Uint8List.fromList(img.encodePng(canvas));
        final pixmap = decodePngToSniIconPixmap(pngBytes);
        expect(pixmap, hasLength(1));
      },
    );

    test(
      'evaluateLinuxTrayEnvironment and buildCleanTrayHostEnvironment handle Wayland and AppImage envs',
      () {
        final ok = evaluateLinuxTrayEnvironment(
          env: const <String, String>{
            'WAYLAND_DISPLAY': 'wayland-0',
            'XDG_RUNTIME_DIR': '/run/user/1000',
          },
          watcherAvailable: true,
        );
        expect(ok.supported, isTrue);

        final cleaned = buildCleanTrayHostEnvironment(const <String, String>{
          'LD_LIBRARY_PATH': '/tmp/.mount_app/usr/lib',
          'SYSTEM_LD_LIBRARY_PATH': '',
        });
        expect(cleaned.containsKey('LD_LIBRARY_PATH'), isFalse);

        String? probedPath;
        final client = openLinuxSessionBus(
          environment: const <String, String>{
            'XDG_RUNTIME_DIR': '/run/user/1000/',
          },
          socketExists: (path) {
            probedPath = path;
            return true;
          },
        );
        expect(probedPath, equals('/run/user/1000/bus'));
        client.close().ignore();
      },
    );
  });
}
