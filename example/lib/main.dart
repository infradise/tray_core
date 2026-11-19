import 'package:flutter/widgets.dart';
import 'package:tray_core/tray_core.dart';

/// Semantic menu icons used in the `tray_core` example.
enum ExampleTrayIcon {
  /// Opens the main workspace window.
  open,

  /// Displays running background worker count.
  workers,

  /// Exits the application.
  quit,
}

/// Entrypoint for the `tray_core` cross-platform tray menu example.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TrayCoreExampleApp());
}

/// Pure `widgets.dart` demonstration of `tray_core` menu modeling and backend
/// selection.
class TrayCoreExampleApp extends StatefulWidget {
  /// Creates a [TrayCoreExampleApp].
  const TrayCoreExampleApp({super.key});

  @override
  State<TrayCoreExampleApp> createState() => _TrayCoreExampleAppState();
}

class _TrayCoreExampleAppState extends State<TrayCoreExampleApp> {
  late final TrayBackend<ExampleTrayIcon> _backend =
      TrayBackend<ExampleTrayIcon>.forCurrentPlatform(
        applicationId: 'tray-core-example',
      );
  int _workerCount = 2;

  List<TrayMenuEntry<ExampleTrayIcon>> _buildEntries() =>
      <TrayMenuEntry<ExampleTrayIcon>>[
        const TrayMenuItemEntry(
          id: 'open',
          label: 'Open Workspace',
          icon: ExampleTrayIcon.open,
        ),
        const TrayMenuSeparatorEntry(),
        TrayMenuItemEntry(
          id: 'workers',
          label: 'Active Workers: $_workerCount',
          icon: ExampleTrayIcon.workers,
        ),
        const TrayMenuSeparatorEntry(),
        const TrayMenuItemEntry(
          id: 'quit',
          label: 'Quit',
          icon: ExampleTrayIcon.quit,
        ),
      ];

  @override
  void dispose() {
    _backend.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries();
    final signature = trayMenuSignature(entries);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF0F172A),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'tray_core — Active Backend: ${_backend.runtimeType}',
                style: const TextStyle(
                  color: Color(0xFFF8FAFC),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Structural Signature: ${signature.replaceAll('\u0000', ' | ')}',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 16),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => _workerCount++);
                    _backend.setMenu(_buildEntries());
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Text(
                        'Increment Worker Count (In-Place Label Update)',
                        style: TextStyle(
                          color: Color(0xFFF8FAFC),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
