import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:tray_core/src/testing/tray_core_testing.dart';
import 'package:tray_core/tray_core.dart';

void main() {
  group('macOS AppKit NSMenuItem UTF-8 and macOS 27+ visibility guard', () {
    test('setMacOSMenuItemImageVisibility safely returns false on nullptr', () {
      expect(setMacOSMenuItemImageVisibility(nullptr, visible: true), isFalse);
      expect(getMacOSMenuItemImageVisibility(nullptr), isNull);
    });

    test(
      'macOS AppKit NSMenuItem initWithTitle:action:keyEquivalent: and setTitle: round-trip non-ASCII labels without NSParameterAssert crash',
      () {
        if (!Platform.isMacOS) return;

        const labels = <String>[
          '',
          'Open Desktop App',
          'Local Services (Running: 3)',
          '    \u25CF worker-node-01  (Active)',
          'Desktop App \u00E9 \u00FC',
          'Workspace Status \u03A9',
          'Desktop App \u2022 Quit',
          '\u{1F680} Quit Desktop App',
        ];
        for (final label in labels) {
          expect(debugCreateMacOSMenuItemTitleRoundTrip(label), equals(label));
        }

        expect(
          debugCreateMacOSMenuItemTitleRoundTrip(
            'Local Services (Running: 0)',
            updatedLabel: 'Local Services (Running: 5)',
          ),
          equals('Local Services (Running: 5)'),
        );

        final loneSurrogate = String.fromCharCodes(<int>[0xD800]);
        expect(
          debugCreateMacOSMenuItemTitleRoundTrip(loneSurrogate),
          equals('\uFFFD'),
        );
      },
    );
  });
}
