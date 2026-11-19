import 'dart:convert' show utf8;
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:tray_core/src/testing/tray_core_testing.dart';
import 'package:tray_core/tray_core.dart';

enum _DemoIcon { open, quit }

List<int> _readNullTerminatedBytes(Pointer<Char> cstr) {
  final ptr = cstr.cast<Uint8>();
  final out = <int>[];
  var i = 0;
  while (ptr[i] != 0) {
    out.add(ptr[i]);
    i++;
  }
  return out;
}

void main() {
  group('tray_core menu model, factory, and UTF-8 marshaling', () {
    test(
      'trayMenuSignature tracks structure and icons while ignoring labels',
      () {
        const a = <TrayMenuEntry<_DemoIcon>>[
          TrayMenuItemEntry(
            id: 'open',
            label: 'Open (1)',
            icon: _DemoIcon.open,
          ),
          TrayMenuSeparatorEntry(),
          TrayMenuItemEntry(id: 'quit', label: 'Quit', icon: _DemoIcon.quit),
        ];
        const b = <TrayMenuEntry<_DemoIcon>>[
          TrayMenuItemEntry(
            id: 'open',
            label: 'Open (99)',
            icon: _DemoIcon.open,
          ),
          TrayMenuSeparatorEntry(),
          TrayMenuItemEntry(id: 'quit', label: 'Quit', icon: _DemoIcon.quit),
        ];
        expect(trayMenuSignature(a), trayMenuSignature(b));
      },
    );

    test('TrayBackend.forCurrentPlatform selects the symmetric OS backend', () {
      final backend = TrayBackend<_DemoIcon>.forCurrentPlatform();
      if (Platform.isLinux) {
        expect(backend, isA<LinuxDbusTrayBackend<_DemoIcon>>());
      } else if (Platform.isMacOS) {
        expect(backend, isA<MacOSTrayBackend<_DemoIcon>>());
      } else if (Platform.isWindows) {
        expect(backend, isA<WindowsTrayBackend<_DemoIcon>>());
      }
      backend.dispose();
    });

    test(
      'populateNativeTrayMenuEntries attaches item to parent menu strictly BEFORE setting icon',
      () {
        final steps = <String>[];
        final outItems = <String>[];
        final outIcons = <_DemoIcon?>[];
        final outIds = <String?>[];

        populateNativeTrayMenuEntries<String, String, _DemoIcon>(
          entries: const <TrayMenuEntry<_DemoIcon>>[
            TrayMenuItemEntry(id: 'open', label: 'Open', icon: _DemoIcon.open),
            TrayMenuSeparatorEntry(),
          ],
          menuImages: const <_DemoIcon, String>{_DemoIcon.open: 'bmp:open'},
          addSeparator: () => steps.add('separator'),
          createItem: (label) {
            steps.add('create:$label');
            return label;
          },
          setEnabled: (item, enabled) => steps.add('enabled:$item:$enabled'),
          attachClickListener: (item, id) => steps.add('click:$id'),
          addItemToMenu: (item) => steps.add('addItemToMenu:$item'),
          setItemIcon: (item, image) => steps.add('setItemIcon:$item:$image'),
          outItems: outItems,
          outItemIcons: outIcons,
          outIds: outIds,
        );

        expect(
          steps,
          equals(<String>[
            'create:Open',
            'enabled:Open:true',
            'click:open',
            'addItemToMenu:Open',
            'setItemIcon:Open:bmp:open',
            'separator',
          ]),
        );
      },
    );

    test(
      'withNullTerminatedUtf8 encodes ASCII, multibyte Unicode, symbol, emoji, NUL, and lone-surrogate strings into valid UTF-8',
      () {
        const samples = <String>[
          '',
          'Open Desktop App',
          'Local Services (Running: 2)',
          '    \u25CF demo-cluster-v1.31  (Built-in)',
          'Desktop App \u00E9 \u00FC',
          'Workspace Status \u03A9',
          'Desktop App \u2022 Settings',
          '\u{1F680} Service Cluster',
        ];
        for (final sample in samples) {
          final bytes = withNullTerminatedUtf8(
            sample,
            _readNullTerminatedBytes,
          );
          expect(bytes, equals(utf8.encode(sample)));
          expect(utf8.decode(bytes), equals(sample));
        }

        final strippedNul = withNullTerminatedUtf8(
          'Desktop\u0000Open',
          _readNullTerminatedBytes,
        );
        expect(utf8.decode(strippedNul), equals('DesktopOpen'));

        final malformed = String.fromCharCodes(<int>[0x41, 0xD800, 0x42]);
        final malformedBytes = withNullTerminatedUtf8(
          malformed,
          _readNullTerminatedBytes,
        );
        expect(() => utf8.decode(malformedBytes), returnsNormally);
        expect(utf8.decode(malformedBytes), equals('A\uFFFDB'));
      },
    );
  });
}
