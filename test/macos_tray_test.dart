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
          'Desktop App 열기',
          '로컬 컨테이너 (실행 중: 3)',
          '    ● redis-sentinel  (Docker)',
          'Desktop App を開く',
          'Mở Desktop App',
          'Desktop App öffnen',
          'Открыть Desktop App',
          '🚀 Desktop App 종료',
        ];
        for (final label in labels) {
          expect(debugCreateMacOSMenuItemTitleRoundTrip(label), equals(label));
        }

        expect(
          debugCreateMacOSMenuItemTitleRoundTrip(
            '로컬 컨테이너 (실행 중: 0)',
            updatedLabel: '로컬 컨테이너 (실행 중: 5)',
          ),
          equals('로컬 컨테이너 (실행 중: 5)'),
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
