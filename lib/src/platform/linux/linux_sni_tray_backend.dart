import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../tray_backend.dart';
import '../../tray_menu_entry.dart';
import 'linux_dbusmenu_object.dart';
import 'linux_tray_environment.dart';

/// Decodes PNG bytes into a `StatusNotifierItem` `IconPixmap` (`a(iiay)`) entry
/// with ARGB32 big-endian pixel ordering.
@visibleForTesting
List<DBusStruct> decodePngToSniIconPixmap(Uint8List pngBytes) {
  try {
    final decoded = img.decodePng(pngBytes);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      return const <DBusStruct>[];
    }
    final argb = Uint8List(decoded.width * decoded.height * 4);
    var offset = 0;
    for (final pixel in decoded) {
      argb[offset++] = (pixel.aNormalized * 255).round().clamp(0, 255);
      argb[offset++] = (pixel.rNormalized * 255).round().clamp(0, 255);
      argb[offset++] = (pixel.gNormalized * 255).round().clamp(0, 255);
      argb[offset++] = (pixel.bNormalized * 255).round().clamp(0, 255);
    }
    return <DBusStruct>[
      DBusStruct(<DBusValue>[
        DBusInt32(decoded.width),
        DBusInt32(decoded.height),
        DBusArray.byte(argb),
      ]),
    ];
  } catch (_) {
    return const <DBusStruct>[];
  }
}

/// Pure-Dart Linux `StatusNotifierItem` (`org.kde.StatusNotifierItem`) and
/// `DBusMenu` (`com.canonical.dbusmenu`) tray backend built on `package:dbus`.
class LinuxDbusTrayBackend<TIcon extends Enum> implements TrayBackend<TIcon> {
  /// Creates a [LinuxDbusTrayBackend].
  LinuxDbusTrayBackend({DBusClient Function()? busOpener, this.applicationId})
    : _busOpener = busOpener ?? openLinuxSessionBus;

  static int _instanceCounter = 0;

  final DBusClient Function() _busOpener;

  /// Optional explicit `StatusNotifierItem.Id` string (defaults to sanitized
  /// tooltip or `'tray_core'`).
  final String? applicationId;

  DBusClient? _client;
  String? _busName;
  _StatusNotifierItemObject? _sniObject;
  TrayDbusMenuObject<TIcon>? _menuObject;
  final DbusMenuStateMachine<TIcon> _menuState = DbusMenuStateMachine<TIcon>();

  @override
  Future<bool> create({
    required String iconPath,
    required String tooltip,
    required void Function() onIconClicked,
    required void Function(String id) onItemSelected,
  }) async {
    dispose();

    final client = _busOpener();
    _client = client;

    try {
      final iconFile = File(iconPath);
      final iconBytes = await iconFile.readAsBytes();
      final iconThemePath = p.dirname(iconFile.path);
      final iconName = p.basenameWithoutExtension(iconFile.path);
      final iconPixmap = decodePngToSniIconPixmap(iconBytes);
      final resolvedId =
          applicationId ??
          (tooltip.trim().isNotEmpty
              ? tooltip.trim().toLowerCase().replaceAll(' ', '-')
              : 'tray_core');

      final sniObject = _StatusNotifierItemObject(
        itemId: resolvedId,
        tooltip: tooltip,
        iconThemePath: iconThemePath,
        iconName: iconName,
        iconPixmap: iconPixmap,
        onActivate: onIconClicked,
      );
      final menuObject = TrayDbusMenuObject<TIcon>(
        state: _menuState,
        onItemSelected: onItemSelected,
      );

      _sniObject = sniObject;
      _menuObject = menuObject;

      await client.registerObject(menuObject);
      await client.registerObject(sniObject);

      final serviceName =
          'org.kde.StatusNotifierItem-$pid-${++_instanceCounter}';
      final nameReply = await client
          .requestName(
            serviceName,
            flags: <DBusRequestNameFlag>{DBusRequestNameFlag.doNotQueue},
          )
          .timeout(const Duration(seconds: 2));
      if (nameReply != DBusRequestNameReply.primaryOwner &&
          nameReply != DBusRequestNameReply.alreadyOwner) {
        dispose();
        return false;
      }
      _busName = serviceName;

      final registered = await _registerWithActiveWatcher(client, serviceName);
      if (!registered) {
        dispose();
        return false;
      }

      return true;
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  Future<bool> _registerWithActiveWatcher(
    DBusClient client,
    String serviceName,
  ) async {
    var registeredAny = false;
    for (final watcherName in linuxStatusNotifierWatcherNames) {
      var owned = false;
      try {
        owned = await client
            .nameHasOwner(watcherName)
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        owned = false;
      }
      if (!owned) continue;

      final interfaces = <String>{watcherName, 'org.kde.StatusNotifierWatcher'};
      for (final iface in interfaces) {
        try {
          await client
              .callMethod(
                destination: watcherName,
                path: DBusObjectPath('/StatusNotifierWatcher'),
                interface: iface,
                name: 'RegisterStatusNotifierItem',
                values: <DBusValue>[DBusString(serviceName)],
                replySignature: DBusSignature(''),
              )
              .timeout(const Duration(seconds: 2));
          registeredAny = true;
          break;
        } catch (_) {
          // Try fallback interface name on this watcher.
        }
      }
    }
    return registeredAny;
  }

  @override
  void setMenuIcons(Map<TIcon, ResolvedTrayMenuIcon<TIcon>> icons) {
    final pngMap = <TIcon, Uint8List>{
      for (final entry in icons.entries) entry.key: entry.value.pngBytes,
    };
    final delta = _menuState.setIcons(pngMap);
    _emitMenuDelta(delta);
  }

  @override
  void setMenu(List<TrayMenuEntry<TIcon>> entries) {
    final delta = _menuState.updateEntries(entries);
    _emitMenuDelta(delta);
  }

  void _emitMenuDelta(DbusMenuUpdateDelta delta) {
    final menuObj = _menuObject;
    if (menuObj == null || menuObj.client == null) return;
    if (delta.updatedProperties.isNotEmpty ||
        delta.removedProperties.isNotEmpty) {
      unawaited(
        menuObj.emitItemsPropertiesUpdated(
          updated: delta.updatedProperties,
          removed: delta.removedProperties,
        ),
      );
    }
    if (delta.layoutChanged) {
      unawaited(menuObj.emitLayoutUpdated(delta.revision));
    }
  }

  @override
  void dispose() {
    final client = _client;
    final busName = _busName;
    final sniObj = _sniObject;
    final menuObj = _menuObject;

    _client = null;
    _busName = null;
    _sniObject = null;
    _menuObject = null;

    if (client == null) return;
    unawaited(() async {
      if (busName != null) {
        try {
          await client
              .releaseName(busName)
              .timeout(const Duration(milliseconds: 500));
        } catch (_) {
          // Bus may already be closed.
        }
      }
      if (sniObj != null && sniObj.client == client) {
        try {
          await client.unregisterObject(sniObj);
        } catch (_) {
          // Object may already be unregistered.
        }
      }
      if (menuObj != null && menuObj.client == client) {
        try {
          await client.unregisterObject(menuObj);
        } catch (_) {
          // Object may already be unregistered.
        }
      }
      try {
        await client.close().timeout(const Duration(seconds: 1));
      } catch (_) {
        // Ignore close timeout on session exit.
      }
    }());
  }
}

/// Symmetric platform alias for [LinuxDbusTrayBackend].
typedef LinuxSniTrayBackend<TIcon extends Enum> = LinuxDbusTrayBackend<TIcon>;

class _StatusNotifierItemObject extends DBusObject {
  _StatusNotifierItemObject({
    required this.itemId,
    required this.tooltip,
    required this.iconThemePath,
    required this.iconName,
    required this.iconPixmap,
    required this.onActivate,
  }) : super(DBusObjectPath('/StatusNotifierItem'));

  static const String _iface = 'org.kde.StatusNotifierItem';

  final String itemId;
  final String tooltip;
  final String iconThemePath;
  final String iconName;
  final List<DBusStruct> iconPixmap;
  final void Function() onActivate;

  Map<String, DBusValue> _allProperties() {
    final emptyPixmaps = DBusArray(
      DBusSignature('(iiay)'),
      const <DBusValue>[],
    );
    return <String, DBusValue>{
      'Category': const DBusString('ApplicationStatus'),
      'Id': DBusString(itemId),
      'Title': DBusString(tooltip),
      'Status': const DBusString('Active'),
      'WindowId': const DBusInt32(0),
      'IconThemePath': DBusString(iconThemePath),
      'Menu': DBusObjectPath('/StatusNotifierItem/Menu'),
      'ItemIsMenu': const DBusBoolean(false),
      'IconName': DBusString(iconName),
      'IconPixmap': DBusArray(DBusSignature('(iiay)'), iconPixmap),
      'OverlayIconName': const DBusString(''),
      'OverlayIconPixmap': emptyPixmaps,
      'AttentionIconName': const DBusString(''),
      'AttentionIconPixmap': emptyPixmaps,
      'AttentionMovieName': const DBusString(''),
    };
  }

  @override
  List<DBusIntrospectInterface> introspect() => <DBusIntrospectInterface>[
    DBusIntrospectInterface(
      _iface,
      methods: <DBusIntrospectMethod>[
        DBusIntrospectMethod(
          'ContextMenu',
          args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.in_,
              name: 'x',
            ),
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.in_,
              name: 'y',
            ),
          ],
        ),
        DBusIntrospectMethod(
          'Activate',
          args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.in_,
              name: 'x',
            ),
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.in_,
              name: 'y',
            ),
          ],
        ),
        DBusIntrospectMethod(
          'ProvideXdgActivationToken',
          args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(
              DBusSignature('s'),
              DBusArgumentDirection.in_,
              name: 'token',
            ),
          ],
        ),
        DBusIntrospectMethod(
          'SecondaryActivate',
          args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.in_,
              name: 'x',
            ),
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.in_,
              name: 'y',
            ),
          ],
        ),
        DBusIntrospectMethod(
          'XAyatanaSecondaryActivate',
          args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(
              DBusSignature('u'),
              DBusArgumentDirection.in_,
              name: 'timestamp',
            ),
          ],
        ),
        DBusIntrospectMethod(
          'Scroll',
          args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.in_,
              name: 'delta',
            ),
            DBusIntrospectArgument(
              DBusSignature('s'),
              DBusArgumentDirection.in_,
              name: 'orientation',
            ),
          ],
        ),
      ],
      signals: <DBusIntrospectSignal>[
        DBusIntrospectSignal('NewTitle'),
        DBusIntrospectSignal('NewIcon'),
        DBusIntrospectSignal('NewAttentionIcon'),
        DBusIntrospectSignal('NewOverlayIcon'),
        DBusIntrospectSignal('NewMenu'),
        DBusIntrospectSignal(
          'NewStatus',
          args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(
              DBusSignature('s'),
              DBusArgumentDirection.out,
              name: 'status',
            ),
          ],
        ),
      ],
      properties: <DBusIntrospectProperty>[
        DBusIntrospectProperty(
          'Category',
          DBusSignature('s'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'Id',
          DBusSignature('s'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'Title',
          DBusSignature('s'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'Status',
          DBusSignature('s'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'WindowId',
          DBusSignature('i'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'IconThemePath',
          DBusSignature('s'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'Menu',
          DBusSignature('o'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'ItemIsMenu',
          DBusSignature('b'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'IconName',
          DBusSignature('s'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'IconPixmap',
          DBusSignature('a(iiay)'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'OverlayIconName',
          DBusSignature('s'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'OverlayIconPixmap',
          DBusSignature('a(iiay)'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'AttentionIconName',
          DBusSignature('s'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'AttentionIconPixmap',
          DBusSignature('a(iiay)'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'AttentionMovieName',
          DBusSignature('s'),
          access: DBusPropertyAccess.read,
        ),
      ],
    ),
  ];

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != _iface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final value = _allProperties()[name];
    if (value == null) {
      return DBusMethodErrorResponse.unknownProperty();
    }
    return DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != _iface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    return DBusGetAllPropertiesResponse(_allProperties());
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != null && methodCall.interface != _iface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (methodCall.name) {
      case 'Activate':
        onActivate();
        return DBusMethodSuccessResponse();
      case 'ContextMenu':
      case 'ProvideXdgActivationToken':
      case 'SecondaryActivate':
      case 'XAyatanaSecondaryActivate':
      case 'Scroll':
        return DBusMethodSuccessResponse();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }
}
