import 'dart:typed_data';

import 'package:dbus/dbus.dart';

import '../../tray_menu_entry.dart';

/// Diff emitted by [DbusMenuStateMachine] so D-Bus signals (`LayoutUpdated` and
/// `ItemsPropertiesUpdated`) can be unit-tested without a live D-Bus daemon.
class DbusMenuUpdateDelta {
  /// Creates a [DbusMenuUpdateDelta].
  const DbusMenuUpdateDelta({
    required this.revision,
    required this.layoutChanged,
    this.updatedProperties = const <(int, Map<String, DBusValue>)>[],
    this.removedProperties = const <(int, List<String>)>[],
  });

  /// Monotonic menu layout revision number.
  final int revision;

  /// Whether the structural menu tree changed (`LayoutUpdated`).
  final bool layoutChanged;

  /// Per-node updated D-Bus property maps (`ItemsPropertiesUpdated`).
  final List<(int, Map<String, DBusValue>)> updatedProperties;

  /// Per-node removed D-Bus property keys (`ItemsPropertiesUpdated`).
  final List<(int, List<String>)> removedProperties;
}

class _MenuNode {
  _MenuNode({
    required this.dbusId,
    required this.entryId,
    required this.properties,
  });

  final int dbusId;
  final String? entryId;
  Map<String, DBusValue> properties;
}

/// Pure in-memory `com.canonical.dbusmenu` layout and property state machine.
class DbusMenuStateMachine<TIcon extends Enum> {
  /// Creates an empty [DbusMenuStateMachine].
  DbusMenuStateMachine();

  int _revision = 1;
  int _nextItemId = 1;
  String? _signature;
  List<TrayMenuEntry<TIcon>> _entries = const <Never>[];
  final List<_MenuNode> _nodes = <_MenuNode>[];
  Map<TIcon, Uint8List> _icons = const <Never, Uint8List>{};

  /// Current `com.canonical.dbusmenu` layout revision.
  int get revision => _revision;

  /// Updates the PNG bytes table keyed by [TIcon].
  DbusMenuUpdateDelta setIcons(Map<TIcon, Uint8List> icons) {
    _icons = Map<TIcon, Uint8List>.unmodifiable(icons);
    if (_nodes.isEmpty) {
      return DbusMenuUpdateDelta(revision: _revision, layoutChanged: false);
    }
    return _updatePropertiesInPlace(_entries);
  }

  /// Applies [entries], reusing item IDs when [trayMenuSignature] matches so
  /// open menus update smoothly via `ItemsPropertiesUpdated`.
  DbusMenuUpdateDelta updateEntries(List<TrayMenuEntry<TIcon>> entries) {
    final nextSignature = trayMenuSignature(entries);
    _entries = List<TrayMenuEntry<TIcon>>.unmodifiable(entries);

    if (_signature != null &&
        nextSignature == _signature &&
        _nodes.length == entries.length) {
      return _updatePropertiesInPlace(entries);
    }

    _signature = nextSignature;
    _nodes
      ..clear()
      ..addAll(<_MenuNode>[
        for (final entry in entries)
          _MenuNode(
            dbusId: _nextItemId++,
            entryId: entry is TrayMenuItemEntry<TIcon> ? entry.id : null,
            properties: _buildPropertiesFor(entry),
          ),
      ]);
    _revision++;
    return DbusMenuUpdateDelta(revision: _revision, layoutChanged: true);
  }

  DbusMenuUpdateDelta _updatePropertiesInPlace(
    List<TrayMenuEntry<TIcon>> entries,
  ) {
    final updated = <(int, Map<String, DBusValue>)>[];
    final removed = <(int, List<String>)>[];

    for (var i = 0; i < entries.length; i++) {
      final node = _nodes[i];
      final nextProps = _buildPropertiesFor(entries[i]);
      final changedProps = <String, DBusValue>{};
      final removedKeys = <String>[];

      for (final kv in nextProps.entries) {
        final prev = node.properties[kv.key];
        if (prev != kv.value) {
          changedProps[kv.key] = kv.value;
        }
      }
      for (final oldKey in node.properties.keys) {
        if (!nextProps.containsKey(oldKey)) {
          removedKeys.add(oldKey);
        }
      }

      node.properties = nextProps;
      if (changedProps.isNotEmpty) {
        updated.add((node.dbusId, changedProps));
      }
      if (removedKeys.isNotEmpty) {
        removed.add((node.dbusId, removedKeys));
      }
    }

    return DbusMenuUpdateDelta(
      revision: _revision,
      layoutChanged: false,
      updatedProperties: updated,
      removedProperties: removed,
    );
  }

  Map<String, DBusValue> _buildPropertiesFor(TrayMenuEntry<TIcon> entry) {
    switch (entry) {
      case TrayMenuSeparatorEntry():
        return <String, DBusValue>{
          'type': const DBusString('separator'),
          'enabled': const DBusBoolean(true),
          'visible': const DBusBoolean(true),
        };
      case TrayMenuItemEntry():
        final png = entry.icon != null ? _icons[entry.icon!] : null;
        return <String, DBusValue>{
          'type': const DBusString('standard'),
          'label': DBusString(entry.label),
          'enabled': DBusBoolean(entry.enabled),
          'visible': const DBusBoolean(true),
          if (png != null && png.isNotEmpty) 'icon-data': DBusArray.byte(png),
        };
    }
  }

  static Map<String, DBusValue> _filterProperties(
    Map<String, DBusValue> source,
    List<String> propertyNames,
  ) {
    if (propertyNames.isEmpty) return source;
    final allowed = propertyNames.toSet();
    return <String, DBusValue>{
      for (final kv in source.entries)
        if (allowed.contains(kv.key)) kv.key: kv.value,
    };
  }

  /// Implements `com.canonical.dbusmenu.GetLayout`.
  (int revision, DBusStruct layout) getLayout({
    required int parentId,
    required int recursionDepth,
    required List<String> propertyNames,
  }) {
    if (parentId == 0) {
      final rootProps = _filterProperties(const <String, DBusValue>{
        'children-display': DBusString('submenu'),
      }, propertyNames);
      final includeChildren = recursionDepth != 0;
      final children =
          includeChildren
              ? <DBusValue>[
                for (final node in _nodes)
                  DBusStruct(<DBusValue>[
                    DBusInt32(node.dbusId),
                    DBusDict.stringVariant(
                      _filterProperties(node.properties, propertyNames),
                    ),
                    DBusArray.variant(const <DBusValue>[]),
                  ]),
              ]
              : const <DBusValue>[];

      return (
        _revision,
        DBusStruct(<DBusValue>[
          const DBusInt32(0),
          DBusDict.stringVariant(rootProps),
          DBusArray.variant(children),
        ]),
      );
    }

    for (final node in _nodes) {
      if (node.dbusId == parentId) {
        return (
          _revision,
          DBusStruct(<DBusValue>[
            DBusInt32(node.dbusId),
            DBusDict.stringVariant(
              _filterProperties(node.properties, propertyNames),
            ),
            DBusArray.variant(const <DBusValue>[]),
          ]),
        );
      }
    }

    return (
      _revision,
      DBusStruct(<DBusValue>[
        DBusInt32(parentId),
        DBusDict.stringVariant(const <String, DBusValue>{}),
        DBusArray.variant(const <DBusValue>[]),
      ]),
    );
  }

  /// Implements `com.canonical.dbusmenu.GetGroupProperties`.
  DBusArray getGroupProperties({
    required List<int> ids,
    required List<String> propertyNames,
  }) {
    final requested = ids.toSet();
    final rows = <DBusStruct>[];

    if (requested.contains(0)) {
      rows.add(
        DBusStruct(<DBusValue>[
          const DBusInt32(0),
          DBusDict.stringVariant(
            _filterProperties(const <String, DBusValue>{
              'children-display': DBusString('submenu'),
            }, propertyNames),
          ),
        ]),
      );
    }

    for (final node in _nodes) {
      if (!requested.contains(node.dbusId)) continue;
      rows.add(
        DBusStruct(<DBusValue>[
          DBusInt32(node.dbusId),
          DBusDict.stringVariant(
            _filterProperties(node.properties, propertyNames),
          ),
        ]),
      );
    }

    return DBusArray(DBusSignature('(ia{sv})'), rows);
  }

  /// Implements `com.canonical.dbusmenu.GetProperty`.
  DBusValue? getPropertyValue(int id, String name) {
    if (id == 0) {
      return name == 'children-display' ? const DBusString('submenu') : null;
    }
    for (final node in _nodes) {
      if (node.dbusId == id) return node.properties[name];
    }
    return null;
  }

  /// Resolves a D-Bus menu item [dbusId] back to its `TrayMenuItemEntry.id`.
  String? entryIdForDbusId(int dbusId) {
    for (final node in _nodes) {
      if (node.dbusId == dbusId) return node.entryId;
    }
    return null;
  }
}

/// D-Bus object exporting `com.canonical.dbusmenu` at
/// `/StatusNotifierItem/Menu`.
class TrayDbusMenuObject<TIcon extends Enum> extends DBusObject {
  /// Creates a [TrayDbusMenuObject] backed by [state].
  TrayDbusMenuObject({required this.state, required this.onItemSelected})
    : super(DBusObjectPath('/StatusNotifierItem/Menu'));

  static const String _iface = 'com.canonical.dbusmenu';

  /// Backing menu layout and property state machine.
  final DbusMenuStateMachine<TIcon> state;

  /// Invoked when a selectable item receives a `"clicked"` D-Bus event.
  final void Function(String id) onItemSelected;

  Map<String, DBusValue> _allProperties() => <String, DBusValue>{
    'Version': const DBusUint32(3),
    'TextDirection': const DBusString('ltr'),
    'Status': const DBusString('normal'),
    'IconThemePath': DBusArray.string(const <String>[]),
  };

  @override
  List<DBusIntrospectInterface> introspect() => <DBusIntrospectInterface>[
    DBusIntrospectInterface(
      _iface,
      methods: <DBusIntrospectMethod>[
        DBusIntrospectMethod(
          'GetLayout',
          args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.in_,
              name: 'parentId',
            ),
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.in_,
              name: 'recursionDepth',
            ),
            DBusIntrospectArgument(
              DBusSignature('as'),
              DBusArgumentDirection.in_,
              name: 'propertyNames',
            ),
            DBusIntrospectArgument(
              DBusSignature('u'),
              DBusArgumentDirection.out,
              name: 'revision',
            ),
            DBusIntrospectArgument(
              DBusSignature('(ia{sv}av)'),
              DBusArgumentDirection.out,
              name: 'layout',
            ),
          ],
        ),
        DBusIntrospectMethod(
          'GetGroupProperties',
          args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(
              DBusSignature('ai'),
              DBusArgumentDirection.in_,
              name: 'ids',
            ),
            DBusIntrospectArgument(
              DBusSignature('as'),
              DBusArgumentDirection.in_,
              name: 'propertyNames',
            ),
            DBusIntrospectArgument(
              DBusSignature('a(ia{sv})'),
              DBusArgumentDirection.out,
              name: 'properties',
            ),
          ],
        ),
        DBusIntrospectMethod(
          'GetProperty',
          args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.in_,
              name: 'id',
            ),
            DBusIntrospectArgument(
              DBusSignature('s'),
              DBusArgumentDirection.in_,
              name: 'name',
            ),
            DBusIntrospectArgument(
              DBusSignature('v'),
              DBusArgumentDirection.out,
              name: 'value',
            ),
          ],
        ),
        DBusIntrospectMethod(
          'Event',
          args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.in_,
              name: 'id',
            ),
            DBusIntrospectArgument(
              DBusSignature('s'),
              DBusArgumentDirection.in_,
              name: 'eventId',
            ),
            DBusIntrospectArgument(
              DBusSignature('v'),
              DBusArgumentDirection.in_,
              name: 'data',
            ),
            DBusIntrospectArgument(
              DBusSignature('u'),
              DBusArgumentDirection.in_,
              name: 'timestamp',
            ),
          ],
        ),
        DBusIntrospectMethod(
          'EventGroup',
          args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(
              DBusSignature('a(isvu)'),
              DBusArgumentDirection.in_,
              name: 'events',
            ),
            DBusIntrospectArgument(
              DBusSignature('ai'),
              DBusArgumentDirection.out,
              name: 'idErrors',
            ),
          ],
        ),
        DBusIntrospectMethod(
          'AboutToShow',
          args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.in_,
              name: 'id',
            ),
            DBusIntrospectArgument(
              DBusSignature('b'),
              DBusArgumentDirection.out,
              name: 'needUpdate',
            ),
          ],
        ),
        DBusIntrospectMethod(
          'AboutToShowGroup',
          args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(
              DBusSignature('ai'),
              DBusArgumentDirection.in_,
              name: 'ids',
            ),
            DBusIntrospectArgument(
              DBusSignature('ai'),
              DBusArgumentDirection.out,
              name: 'updatesNeeded',
            ),
            DBusIntrospectArgument(
              DBusSignature('ai'),
              DBusArgumentDirection.out,
              name: 'idErrors',
            ),
          ],
        ),
      ],
      signals: <DBusIntrospectSignal>[
        DBusIntrospectSignal(
          'ItemsPropertiesUpdated',
          args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(
              DBusSignature('a(ia{sv})'),
              DBusArgumentDirection.out,
              name: 'updatedProps',
            ),
            DBusIntrospectArgument(
              DBusSignature('a(ias)'),
              DBusArgumentDirection.out,
              name: 'removedProps',
            ),
          ],
        ),
        DBusIntrospectSignal(
          'LayoutUpdated',
          args: <DBusIntrospectArgument>[
            DBusIntrospectArgument(
              DBusSignature('u'),
              DBusArgumentDirection.out,
              name: 'revision',
            ),
            DBusIntrospectArgument(
              DBusSignature('i'),
              DBusArgumentDirection.out,
              name: 'parent',
            ),
          ],
        ),
      ],
      properties: <DBusIntrospectProperty>[
        DBusIntrospectProperty(
          'Version',
          DBusSignature('u'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'TextDirection',
          DBusSignature('s'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'Status',
          DBusSignature('s'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'IconThemePath',
          DBusSignature('as'),
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
      case 'GetLayout':
        if (methodCall.values.length < 3) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        final parentId = methodCall.values[0].asInt32();
        final recursionDepth = methodCall.values[1].asInt32();
        final propNames = methodCall.values[2].asStringArray().toList();
        final (rev, layout) = state.getLayout(
          parentId: parentId,
          recursionDepth: recursionDepth,
          propertyNames: propNames,
        );
        return DBusMethodSuccessResponse(<DBusValue>[DBusUint32(rev), layout]);

      case 'GetGroupProperties':
        if (methodCall.values.length < 2) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        final ids = methodCall.values[0].asInt32Array().toList();
        final propNames = methodCall.values[1].asStringArray().toList();
        final group = state.getGroupProperties(
          ids: ids,
          propertyNames: propNames,
        );
        return DBusMethodSuccessResponse(<DBusValue>[group]);

      case 'GetProperty':
        if (methodCall.values.length < 2) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        final id = methodCall.values[0].asInt32();
        final name = methodCall.values[1].asString();
        final val = state.getPropertyValue(id, name);
        if (val == null) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        return DBusMethodSuccessResponse(<DBusValue>[DBusVariant(val)]);

      case 'Event':
        if (methodCall.values.length >= 2) {
          final id = methodCall.values[0].asInt32();
          final eventId = methodCall.values[1].asString();
          if (eventId == 'clicked') {
            final entryId = state.entryIdForDbusId(id);
            if (entryId != null) onItemSelected(entryId);
          }
        }
        return DBusMethodSuccessResponse();

      case 'EventGroup':
        if (methodCall.values.isNotEmpty && methodCall.values[0] is DBusArray) {
          final array = methodCall.values[0] as DBusArray;
          for (final child in array.children) {
            if (child is DBusStruct && child.children.length >= 2) {
              final id = child.children[0].asInt32();
              final eventId = child.children[1].asString();
              if (eventId == 'clicked') {
                final entryId = state.entryIdForDbusId(id);
                if (entryId != null) onItemSelected(entryId);
              }
            }
          }
        }
        return DBusMethodSuccessResponse(<DBusValue>[
          DBusArray.int32(const <int>[]),
        ]);

      case 'AboutToShow':
        return DBusMethodSuccessResponse(const <DBusValue>[DBusBoolean(false)]);

      case 'AboutToShowGroup':
        return DBusMethodSuccessResponse(<DBusValue>[
          DBusArray.int32(const <int>[]),
          DBusArray.int32(const <int>[]),
        ]);

      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  /// Emits `com.canonical.dbusmenu.LayoutUpdated`.
  Future<void> emitLayoutUpdated(int revision) async {
    try {
      await emitSignal(_iface, 'LayoutUpdated', <DBusValue>[
        DBusUint32(revision),
        const DBusInt32(0),
      ]);
    } catch (_) {
      // Ignore transient D-Bus disconnects during teardown.
    }
  }

  /// Emits `com.canonical.dbusmenu.ItemsPropertiesUpdated`.
  Future<void> emitItemsPropertiesUpdated({
    required List<(int, Map<String, DBusValue>)> updated,
    required List<(int, List<String>)> removed,
  }) async {
    try {
      await emitSignal(_iface, 'ItemsPropertiesUpdated', <DBusValue>[
        DBusArray(DBusSignature('(ia{sv})'), <DBusValue>[
          for (final (id, props) in updated)
            DBusStruct(<DBusValue>[
              DBusInt32(id),
              DBusDict.stringVariant(props),
            ]),
        ]),
        DBusArray(DBusSignature('(ias)'), <DBusValue>[
          for (final (id, keys) in removed)
            DBusStruct(<DBusValue>[DBusInt32(id), DBusArray.string(keys)]),
        ]),
      ]);
    } catch (_) {
      // Ignore transient D-Bus disconnects during teardown.
    }
  }
}
