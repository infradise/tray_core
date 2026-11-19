import 'package:flutter_test/flutter_test.dart';
import 'package:tray_core_example/main.dart';

void main() {
  testWidgets('TrayCoreExampleApp renders backend info and updates signature', (
    tester,
  ) async {
    await tester.pumpWidget(const TrayCoreExampleApp());

    expect(find.textContaining('tray_core — Active Backend:'), findsOneWidget);
    expect(find.textContaining('Structural Signature:'), findsOneWidget);
    expect(
      find.text('Increment Worker Count (In-Place Label Update)'),
      findsOneWidget,
    );

    await tester.tap(
      find.text('Increment Worker Count (In-Place Label Update)'),
    );
    await tester.pump();
    expect(find.textContaining('Structural Signature:'), findsOneWidget);
  });
}
