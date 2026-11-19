import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Result of the Linux system tray pre-flight / remediation check.
class LinuxTrayReport {
  /// Creates a [LinuxTrayReport].
  const LinuxTrayReport({
    required this.supported,
    required this.reason,
    this.canInstallGnomeExtension = false,
  });

  /// Whether an active `StatusNotifierWatcher` is ready on the session bus.
  final bool supported;

  /// Human-readable diagnostic explanation.
  final String reason;

  /// Whether GNOME Shell's `InstallRemoteExtension` prompt can install
  /// AppIndicator support interactively.
  final bool canInstallGnomeExtension;

  @override
  String toString() =>
      'LinuxTrayReport(supported: $supported, '
      'canInstallGnomeExtension: $canInstallGnomeExtension, reason: $reason)';
}

/// Result of checking or enabling a GNOME Shell AppIndicator tray extension.
class GnomeTrayRemediationResult {
  /// Creates a [GnomeTrayRemediationResult].
  const GnomeTrayRemediationResult({
    required this.watcherReady,
    required this.gnomeDetected,
    this.installedExtensionUuid,
    this.canInstallRemotely = false,
    this.reason = '',
  });

  /// Whether `StatusNotifierWatcher` became reachable after remediation.
  final bool watcherReady;

  /// Whether a GNOME Shell desktop session was detected.
  final bool gnomeDetected;

  /// UUID of the installed AppIndicator extension if found on disk or D-Bus.
  final String? installedExtensionUuid;

  /// Whether remote installation via GNOME Shell D-Bus is available.
  final bool canInstallRemotely;

  /// Diagnostic outcome description.
  final String reason;
}

/// Handle returned by [subscribeStatusNotifierWatcherChanges].
class LinuxTrayWatcherSubscription {
  /// Creates a [LinuxTrayWatcherSubscription] invoking [_onCancel] once.
  LinuxTrayWatcherSubscription(this._onCancel);

  final void Function() _onCancel;
  bool _cancelled = false;

  /// Cancels the D-Bus `NameOwnerChanged` listener and closes its bus client.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel();
  }
}

/// Callback signature for subscribing to `StatusNotifierWatcher` availability
/// changes.
typedef LinuxWatcherSubscriber =
    LinuxTrayWatcherSubscription? Function(
      void Function(bool available) onChanged,
    );

/// Well-known bus names under which a `StatusNotifierWatcher` is published
/// across KDE Plasma, GNOME AppIndicator, Ubuntu, XFCE, Cinnamon, MATE, and
/// Waybar.
const List<String> linuxStatusNotifierWatcherNames = <String>[
  'org.kde.StatusNotifierWatcher',
  'org.freedesktop.StatusNotifierWatcher',
  'com.canonical.StatusNotifierWatcher',
];

/// Known GNOME Shell extensions that provide StatusNotifier / AppIndicator
/// support in the top bar, ordered by preference.
const List<String> linuxGnomeTrayExtensionUuids = <String>[
  'appindicatorsupport@rgcjonas.gmail.com',
  'ubuntu-appindicators@ubuntu.com',
  'trayIconsReloaded@selfmade.pl',
  'topiconsfix@aleskva.dev',
  'TopIcons@phocean.net',
];

/// Official GNOME AppIndicator extension UUID (`extensions.gnome.org` / Fedora
/// / Ubuntu / Arch).
const String kDefaultGnomeAppIndicatorUuid =
    'appindicatorsupport@rgcjonas.gmail.com';

const String _gnomeExtensionsPath = '/org/gnome/Shell/Extensions';
const String _gnomeExtensionsInterface = 'org.gnome.Shell.Extensions';
const List<String> _gnomeExtensionsDestinations = <String>[
  'org.gnome.Shell.Extensions',
  'org.gnome.Shell',
];

/// Builds a clean host environment when spawning host utilities
/// (`gnome-extensions`) from inside an AppImage (`SYSTEM_LD_LIBRARY_PATH`
/// restoration).
@visibleForTesting
Map<String, String> buildCleanTrayHostEnvironment([
  Map<String, String>? sourceEnv,
]) {
  final env = Map<String, String>.from(sourceEnv ?? Platform.environment);
  if (env.containsKey('SYSTEM_LD_LIBRARY_PATH')) {
    final original = (env['SYSTEM_LD_LIBRARY_PATH'] ?? '').trim();
    if (original.isNotEmpty) {
      env['LD_LIBRARY_PATH'] = original;
    } else {
      env.remove('LD_LIBRARY_PATH');
    }
  }
  return env;
}

String _stripTrailingSlashes(String path) {
  var end = path.length;
  while (end > 1 && path.codeUnitAt(end - 1) == 0x2F) {
    end--;
  }
  return end == path.length ? path : path.substring(0, end);
}

/// Opens a [DBusClient] connected to the user's session bus (with Wayland
/// `$XDG_RUNTIME_DIR/bus` fallback).
DBusClient openLinuxSessionBus({
  Map<String, String>? environment,
  bool Function(String path)? socketExists,
}) {
  final env = environment ?? Platform.environment;
  final address = (env['DBUS_SESSION_BUS_ADDRESS'] ?? '').trim();
  if (address.isNotEmpty) {
    return DBusClient(DBusAddress(address));
  }

  final runtimeDir = _stripTrailingSlashes(
    (env['XDG_RUNTIME_DIR'] ?? '').trim(),
  );
  if (runtimeDir.isNotEmpty) {
    final socketPath = '$runtimeDir/bus';
    final exists =
        socketExists ??
        (String p) =>
            FileSystemEntity.typeSync(p) != FileSystemEntityType.notFound;
    if (exists(socketPath)) {
      return DBusClient(DBusAddress.unix(path: socketPath));
    }
  }

  return DBusClient.session();
}

void _closeBusSafely(DBusClient? client) {
  if (client == null) return;
  unawaited(
    client
        .close()
        .timeout(const Duration(seconds: 1))
        .catchError((Object _) {}),
  );
}

/// Returns whether [env] indicates a GNOME-based desktop session.
@visibleForTesting
bool isGnomeDesktopEnvironment(Map<String, String> env) {
  final combined =
      <String?>[
        env['XDG_CURRENT_DESKTOP'],
        env['XDG_SESSION_DESKTOP'],
        env['DESKTOP_SESSION'],
        env['GDMSESSION'],
      ].whereType<String>().join(':').toLowerCase();
  return combined.contains('gnome') || combined.contains('ubuntu');
}

/// Pure decision function evaluating Linux tray availability without I/O.
LinuxTrayReport evaluateLinuxTrayEnvironment({
  required Map<String, String> env,
  required bool? watcherAvailable,
  bool canInstallGnomeExtension = false,
}) {
  bool has(String key) => (env[key] ?? '').trim().isNotEmpty;

  if (!has('DISPLAY') && !has('WAYLAND_DISPLAY')) {
    return const LinuxTrayReport(
      supported: false,
      reason: 'No graphical session (DISPLAY / WAYLAND_DISPLAY not set).',
    );
  }
  if (!has('DBUS_SESSION_BUS_ADDRESS') && !has('XDG_RUNTIME_DIR')) {
    return const LinuxTrayReport(
      supported: false,
      reason:
          'No DBus session bus (DBUS_SESSION_BUS_ADDRESS / XDG_RUNTIME_DIR not set).',
    );
  }
  if (watcherAvailable == null) {
    return const LinuxTrayReport(
      supported: false,
      reason: 'DBus session bus is not reachable.',
    );
  }
  if (!watcherAvailable) {
    return LinuxTrayReport(
      supported: false,
      canInstallGnomeExtension: canInstallGnomeExtension,
      reason:
          'No StatusNotifierWatcher on the session bus '
          '(e.g. GNOME without the AppIndicator extension).',
    );
  }
  return const LinuxTrayReport(
    supported: true,
    reason: 'StatusNotifierWatcher found.',
  );
}

Future<bool> _busNameHasOwner(
  DBusClient client,
  String name, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final reply = await client
      .callMethod(
        destination: 'org.freedesktop.DBus',
        path: DBusObjectPath('/org/freedesktop/DBus'),
        interface: 'org.freedesktop.DBus',
        name: 'NameHasOwner',
        values: <DBusValue>[DBusString(name)],
        replySignature: DBusSignature('b'),
      )
      .timeout(timeout);
  return reply.returnValues.isNotEmpty &&
      reply.returnValues.first is DBusBoolean &&
      (reply.returnValues.first as DBusBoolean).value;
}

/// Asks the session bus whether any `StatusNotifierWatcher` owns its bus name.
/// Never throws.
Future<bool?> probeStatusNotifierWatcher({
  Map<String, String>? environment,
  Duration timeout = const Duration(seconds: 2),
}) async {
  DBusClient? client;
  try {
    client = openLinuxSessionBus(environment: environment);
    final c = client;
    return await () async {
      for (final name in linuxStatusNotifierWatcherNames) {
        if (await _busNameHasOwner(c, name, timeout: timeout)) {
          return true;
        }
      }
      return false;
    }().timeout(timeout);
  } catch (_) {
    return null;
  } finally {
    _closeBusSafely(client);
  }
}

/// Attempts D-Bus service activation (`StartServiceByName`) for any registered
/// `StatusNotifierWatcher` service on the session bus. Never throws.
Future<bool> activateStatusNotifierWatcherViaDBus({
  Map<String, String>? environment,
  Duration timeout = const Duration(seconds: 2),
}) async {
  DBusClient? client;
  try {
    client = openLinuxSessionBus(environment: environment);
    final c = client;
    for (final name in linuxStatusNotifierWatcherNames) {
      try {
        final reply = await c
            .callMethod(
              destination: 'org.freedesktop.DBus',
              path: DBusObjectPath('/org/freedesktop/DBus'),
              interface: 'org.freedesktop.DBus',
              name: 'StartServiceByName',
              values: <DBusValue>[DBusString(name), const DBusUint32(0)],
              replySignature: DBusSignature('u'),
            )
            .timeout(timeout);
        if (reply.returnValues.isNotEmpty &&
            reply.returnValues.first is DBusUint32) {
          final code = (reply.returnValues.first as DBusUint32).value;
          if (code == 1 || code == 2) return true;
        }
      } catch (_) {
        // Ignore unregistered watcher name and continue probing remaining names.
      }
    }
    return false;
  } catch (_) {
    return false;
  } finally {
    _closeBusSafely(client);
  }
}

/// Polls [watcherProbe] until a `StatusNotifierWatcher` owns its bus name or
/// [maxWait] elapses.
@visibleForTesting
Future<bool> waitForStatusNotifierWatcher({
  required Future<bool?> Function() watcherProbe,
  Duration maxWait = const Duration(milliseconds: 2500),
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(maxWait);
  while (true) {
    final ok = await watcherProbe();
    if (ok == true) return true;
    if (DateTime.now().isAfter(deadline)) return false;
    await Future<void>.delayed(pollInterval);
  }
}

String? _findInstalledGnomeTrayExtensionOnDisk(
  Map<String, String> env, {
  bool Function(String path)? directoryExists,
}) {
  final exists = directoryExists ?? (String p) => Directory(p).existsSync();
  final home = _stripTrailingSlashes((env['HOME'] ?? '').trim());
  final roots = <String>[
    if (home.isNotEmpty) '$home/.local/share/gnome-shell/extensions',
    '/usr/share/gnome-shell/extensions',
    '/usr/local/share/gnome-shell/extensions',
  ];

  for (final uuid in linuxGnomeTrayExtensionUuids) {
    for (final root in roots) {
      if (exists('$root/$uuid')) return uuid;
    }
  }
  return null;
}

Future<String?> _resolveActiveGnomeExtensionsDestination(
  DBusClient client,
  Map<String, String> env,
) async {
  try {
    final shellOwned = await _busNameHasOwner(client, 'org.gnome.Shell');
    if (!shellOwned && !isGnomeDesktopEnvironment(env)) {
      return null;
    }
  } catch (_) {
    if (!isGnomeDesktopEnvironment(env)) return null;
  }

  for (final dest in _gnomeExtensionsDestinations) {
    try {
      await client
          .callMethod(
            destination: dest,
            path: DBusObjectPath(_gnomeExtensionsPath),
            interface: 'org.freedesktop.DBus.Properties',
            name: 'Get',
            values: const <DBusValue>[
              DBusString(_gnomeExtensionsInterface),
              DBusString('ShellVersion'),
            ],
            replySignature: DBusSignature('v'),
          )
          .timeout(const Duration(seconds: 2));
      return dest;
    } catch (_) {
      // Probe next GNOME Shell D-Bus destination.
    }
  }
  return null;
}

Future<Set<String>> _listGnomeInstalledExtensionUuids(
  DBusClient client,
  String destination,
) async {
  final reply = await client
      .callMethod(
        destination: destination,
        path: DBusObjectPath(_gnomeExtensionsPath),
        interface: _gnomeExtensionsInterface,
        name: 'ListExtensions',
        replySignature: DBusSignature('a{sa{sv}}'),
      )
      .timeout(const Duration(seconds: 2));

  if (reply.returnValues.isEmpty || reply.returnValues.first is! DBusDict) {
    return const <String>{};
  }
  final dict = reply.returnValues.first as DBusDict;
  final result = <String>{};
  for (final key in dict.children.keys) {
    if (key is DBusString && key.value.isNotEmpty) {
      result.add(key.value);
    }
  }
  return result;
}

Future<void> _ensureGnomeUserExtensionsMasterSwitch(
  DBusClient client,
  String destination,
) async {
  try {
    final getReply = await client
        .callMethod(
          destination: destination,
          path: DBusObjectPath(_gnomeExtensionsPath),
          interface: 'org.freedesktop.DBus.Properties',
          name: 'Get',
          values: const <DBusValue>[
            DBusString(_gnomeExtensionsInterface),
            DBusString('UserExtensionsEnabled'),
          ],
          replySignature: DBusSignature('v'),
        )
        .timeout(const Duration(seconds: 2));
    if (getReply.returnValues.isNotEmpty &&
        getReply.returnValues.first is DBusVariant) {
      final inner = (getReply.returnValues.first as DBusVariant).value;
      if (inner is DBusBoolean && !inner.value) {
        await client
            .callMethod(
              destination: destination,
              path: DBusObjectPath(_gnomeExtensionsPath),
              interface: 'org.freedesktop.DBus.Properties',
              name: 'Set',
              values: const <DBusValue>[
                DBusString(_gnomeExtensionsInterface),
                DBusString('UserExtensionsEnabled'),
                DBusVariant(DBusBoolean(true)),
              ],
            )
            .timeout(const Duration(seconds: 2));
      }
    }
  } catch (_) {
    // Master switch property may be read-only or absent on older GNOME builds.
  }
}

Future<bool> _enableGnomeExtensionViaDBus(
  DBusClient client,
  String destination,
  String uuid,
) async {
  await _ensureGnomeUserExtensionsMasterSwitch(client, destination);
  final reply = await client
      .callMethod(
        destination: destination,
        path: DBusObjectPath(_gnomeExtensionsPath),
        interface: _gnomeExtensionsInterface,
        name: 'EnableExtension',
        values: <DBusValue>[DBusString(uuid)],
        replySignature: DBusSignature('b'),
      )
      .timeout(const Duration(seconds: 3));
  return reply.returnValues.isNotEmpty &&
      reply.returnValues.first is DBusBoolean &&
      (reply.returnValues.first as DBusBoolean).value;
}

Future<bool> _enableGnomeExtensionViaCli(
  String uuid,
  Map<String, String> env,
) async {
  try {
    final cleanEnv = buildCleanTrayHostEnvironment(env);
    const candidates = <String>[
      '/usr/bin/gnome-extensions',
      '/usr/local/bin/gnome-extensions',
      'gnome-extensions',
    ];
    for (final bin in candidates) {
      if (bin.startsWith('/') && !File(bin).existsSync()) continue;
      final result = await Process.run(bin, <String>[
        'enable',
        uuid,
      ], environment: cleanEnv).timeout(const Duration(seconds: 3));
      if (result.exitCode == 0) return true;
    }
  } catch (_) {
    // Fall through if CLI binary is missing or times out.
  }
  return false;
}

/// Enables an installed GNOME AppIndicator extension so `StatusNotifierWatcher`
/// becomes available immediately. Never throws.
Future<GnomeTrayRemediationResult> ensureGnomeTrayExtensionEnabled({
  Map<String, String>? environment,
  Future<bool?> Function()? watcherProbe,
  bool Function(String path)? directoryExists,
}) async {
  final env = environment ?? Platform.environment;
  final probe =
      watcherProbe ?? () => probeStatusNotifierWatcher(environment: env);
  DBusClient? client;

  try {
    client = openLinuxSessionBus(environment: env);
    final c = client;
    final dest = await _resolveActiveGnomeExtensionsDestination(c, env);
    if (dest == null) {
      return const GnomeTrayRemediationResult(
        watcherReady: false,
        gnomeDetected: false,
        reason: 'Not a GNOME Shell session.',
      );
    }

    var installedUuids = const <String>{};
    try {
      installedUuids = await _listGnomeInstalledExtensionUuids(c, dest);
    } catch (_) {
      // Fall back to filesystem extension scan below.
    }

    String? targetUuid;
    for (final candidate in linuxGnomeTrayExtensionUuids) {
      if (installedUuids.contains(candidate)) {
        targetUuid = candidate;
        break;
      }
    }
    targetUuid ??= _findInstalledGnomeTrayExtensionOnDisk(
      env,
      directoryExists: directoryExists,
    );

    if (targetUuid == null) {
      return const GnomeTrayRemediationResult(
        watcherReady: false,
        gnomeDetected: true,
        canInstallRemotely: true,
        reason: 'GNOME Shell has no AppIndicator extension installed.',
      );
    }

    var enabled = false;
    try {
      enabled = await _enableGnomeExtensionViaDBus(c, dest, targetUuid);
    } catch (_) {
      enabled = false;
    }

    if (!enabled) {
      await _enableGnomeExtensionViaCli(targetUuid, env);
    }

    final ready = await waitForStatusNotifierWatcher(watcherProbe: probe);
    return GnomeTrayRemediationResult(
      watcherReady: ready,
      gnomeDetected: true,
      installedExtensionUuid: targetUuid,
      canInstallRemotely: !ready,
      reason:
          ready
              ? 'Enabled GNOME tray extension ($targetUuid).'
              : 'GNOME tray extension ($targetUuid) did not expose StatusNotifierWatcher in time.',
    );
  } catch (e) {
    return GnomeTrayRemediationResult(
      watcherReady: false,
      gnomeDetected: isGnomeDesktopEnvironment(env),
      reason: 'GNOME extension check failed: $e',
    );
  } finally {
    _closeBusSafely(client);
  }
}

/// Installs (if missing) and enables the GNOME AppIndicator extension via
/// GNOME Shell's native `InstallRemoteExtension` D-Bus prompt. Never throws.
Future<LinuxTrayReport> installAndEnableLinuxGnomeTray({
  Map<String, String>? environment,
  Future<bool?> Function()? watcherProbe,
}) async {
  final env = environment ?? Platform.environment;
  final probe =
      watcherProbe ?? () => probeStatusNotifierWatcher(environment: env);

  final existing = await ensureGnomeTrayExtensionEnabled(
    environment: env,
    watcherProbe: probe,
  );
  if (existing.watcherReady) {
    return LinuxTrayReport(supported: true, reason: existing.reason);
  }

  DBusClient? client;
  try {
    client = openLinuxSessionBus(environment: env);
    final c = client;
    final dest = await _resolveActiveGnomeExtensionsDestination(c, env);
    if (dest == null) {
      return const LinuxTrayReport(
        supported: false,
        reason: 'GNOME Shell Extensions DBus service is not available.',
      );
    }

    await c
        .callMethod(
          destination: dest,
          path: DBusObjectPath(_gnomeExtensionsPath),
          interface: _gnomeExtensionsInterface,
          name: 'InstallRemoteExtension',
          values: const <DBusValue>[DBusString(kDefaultGnomeAppIndicatorUuid)],
          replySignature: DBusSignature('s'),
        )
        .timeout(const Duration(seconds: 60));

    try {
      await _enableGnomeExtensionViaDBus(
        c,
        dest,
        kDefaultGnomeAppIndicatorUuid,
      );
    } catch (_) {
      await _enableGnomeExtensionViaCli(kDefaultGnomeAppIndicatorUuid, env);
    }

    final ready = await waitForStatusNotifierWatcher(
      watcherProbe: probe,
      maxWait: const Duration(seconds: 5),
    );
    return evaluateLinuxTrayEnvironment(
      env: env,
      watcherAvailable: ready,
      canInstallGnomeExtension: !ready,
    );
  } catch (e) {
    return LinuxTrayReport(
      supported: false,
      canInstallGnomeExtension: true,
      reason: 'GNOME AppIndicator installation cancelled or failed: $e',
    );
  } finally {
    _closeBusSafely(client);
  }
}

/// Subscribes to D-Bus `NameOwnerChanged` signals for all known
/// `StatusNotifierWatcher` bus names. Never throws.
LinuxTrayWatcherSubscription? subscribeStatusNotifierWatcherChanges(
  void Function(bool available) onChanged, {
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final hasBus =
      (env['DBUS_SESSION_BUS_ADDRESS'] ?? '').trim().isNotEmpty ||
      (env['XDG_RUNTIME_DIR'] ?? '').trim().isNotEmpty;
  if (!hasBus) return null;

  DBusClient? client;
  StreamSubscription<DBusSignal>? sub;
  try {
    client = openLinuxSessionBus(environment: env);
    final stream = DBusSignalStream(
      client,
      sender: 'org.freedesktop.DBus',
      interface: 'org.freedesktop.DBus',
      name: 'NameOwnerChanged',
      path: DBusObjectPath('/org/freedesktop/DBus'),
    );

    sub = stream.listen((signal) async {
      if (signal.values.length < 3) return;
      final busName = signal.values[0];
      final newOwner = signal.values[2];
      if (busName is! DBusString || newOwner is! DBusString) return;
      if (!linuxStatusNotifierWatcherNames.contains(busName.value)) return;

      if (newOwner.value.isNotEmpty) {
        onChanged(true);
      } else {
        final stillOwned =
            await probeStatusNotifierWatcher(environment: env) ?? false;
        if (!stillOwned) {
          onChanged(false);
        }
      }
    }, onError: (Object _) {});

    return LinuxTrayWatcherSubscription(() {
      unawaited(sub?.cancel().catchError((Object _) {}));
      _closeBusSafely(client);
    });
  } catch (_) {
    unawaited(sub?.cancel().catchError((Object _) {}));
    _closeBusSafely(client);
    return null;
  }
}

/// Full pre-flight and auto-remediation check for the current Linux session.
/// Never throws.
Future<LinuxTrayReport> checkLinuxTraySupport({
  Map<String, String>? environment,
  Future<bool?> Function()? watcherProbe,
  Future<bool> Function()? serviceActivator,
  Future<GnomeTrayRemediationResult> Function()? gnomeRemediator,
}) async {
  try {
    final env = environment ?? Platform.environment;
    final graphical =
        (env['DISPLAY'] ?? '').trim().isNotEmpty ||
        (env['WAYLAND_DISPLAY'] ?? '').trim().isNotEmpty;
    final busKnown =
        (env['DBUS_SESSION_BUS_ADDRESS'] ?? '').trim().isNotEmpty ||
        (env['XDG_RUNTIME_DIR'] ?? '').trim().isNotEmpty;

    bool? watcher;
    var canInstallGnome = false;

    if (graphical && busKnown) {
      final probe =
          watcherProbe ?? () => probeStatusNotifierWatcher(environment: env);
      watcher = await probe();

      if (watcher == false) {
        final activator =
            serviceActivator ??
            (watcherProbe == null
                ? () => activateStatusNotifierWatcherViaDBus(environment: env)
                : null);
        if (activator != null && await activator()) {
          watcher = await probe();
        }
      }

      if (watcher == false) {
        final remediator =
            gnomeRemediator ??
            (watcherProbe == null
                ? () => ensureGnomeTrayExtensionEnabled(
                  environment: env,
                  watcherProbe: probe,
                )
                : null);
        if (remediator != null) {
          final gnome = await remediator();
          if (gnome.watcherReady) {
            watcher = true;
          } else if (gnome.canInstallRemotely) {
            canInstallGnome = true;
          }
        }
      }
    }

    return evaluateLinuxTrayEnvironment(
      env: env,
      watcherAvailable: watcher,
      canInstallGnomeExtension: canInstallGnome,
    );
  } catch (e) {
    return LinuxTrayReport(
      supported: false,
      reason: 'Pre-flight check failed: $e',
    );
  }
}
