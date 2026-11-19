import 'dart:typed_data';

/// Trigger mode for displaying the native tray context menu.
enum ContextMenuTrigger {
  /// Context menu is never opened automatically by the OS tray host.
  none,

  /// Context menu opens on primary (left) click (macOS menu bar standard).
  clicked,

  /// Context menu opens on secondary (right) click (Windows & Linux standard).
  rightClicked,

  /// Context menu opens on either primary or secondary click.
  anyClicked,
}

/// Rasterized PNG representation of a tray menu icon key [TIcon].
class ResolvedTrayMenuIcon<TIcon extends Enum> {
  /// Creates a [ResolvedTrayMenuIcon] pairing [icon] with its [pngBytes] and
  /// on-disk [filePath].
  const ResolvedTrayMenuIcon({
    required this.icon,
    required this.pngBytes,
    required this.filePath,
  });

  /// Semantic icon enum key.
  final TIcon icon;

  /// Encoded PNG bytes (used directly by Linux `com.canonical.dbusmenu`
  /// `icon-data`).
  final Uint8List pngBytes;

  /// Path to the rasterized PNG file on disk (used by macOS `NSImage` and
  /// Windows `CreateDIBSection` loaders).
  final String filePath;
}

/// One entry of the system tray context menu.
sealed class TrayMenuEntry<TIcon extends Enum> {
  /// Creates a [TrayMenuEntry].
  const TrayMenuEntry();
}

/// A selectable menu item entry in the system tray context menu.
class TrayMenuItemEntry<TIcon extends Enum> extends TrayMenuEntry<TIcon> {
  /// Creates a selectable [TrayMenuItemEntry].
  const TrayMenuItemEntry({
    required this.id,
    required this.label,
    this.icon,
    this.enabled = true,
  });

  /// Stable action identifier passed to `onItemSelected` when clicked.
  final String id;

  /// Localized display text of the menu item.
  final String label;

  /// Optional leading icon key.
  final TIcon? icon;

  /// Whether the item is interactive (`true`) or disabled/grayed (`false`).
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is TrayMenuItemEntry &&
      other.id == id &&
      other.label == label &&
      other.icon == icon &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(id, label, icon, enabled);

  @override
  String toString() =>
      'TrayMenuItemEntry($id, "$label", icon: ${icon?.name}, enabled: $enabled)';
}

/// A horizontal separator entry in the system tray context menu.
class TrayMenuSeparatorEntry<TIcon extends Enum> extends TrayMenuEntry<TIcon> {
  /// Creates a [TrayMenuSeparatorEntry].
  const TrayMenuSeparatorEntry();

  @override
  bool operator ==(Object other) => other is TrayMenuSeparatorEntry;

  @override
  int get hashCode => 0x5e9;
}

/// Structural signature (`ids` + `icons` + separators, excluding labels).
///
/// When this signature is unchanged, the native or D-Bus menu updates labels
/// and enabled states in place rather than rebuilding the menu tree.
String trayMenuSignature<TIcon extends Enum>(
  List<TrayMenuEntry<TIcon>> entries,
) => entries
    .map(
      (e) => switch (e) {
        TrayMenuItemEntry(:final id, :final icon) => '$id:${icon?.name ?? ''}',
        TrayMenuSeparatorEntry() => '-',
      },
    )
    .join('\u0000');

/// Populates a native tray menu from [entries], strictly invoking
/// [addItemToMenu] BEFORE [setItemIcon] so Win32
/// `SetMenuItemInfoW(..., MIIM_BITMAP)` always has a valid parent `HMENU`.
void populateNativeTrayMenuEntries<
  TItem extends Object,
  TImage extends Object,
  TIcon extends Enum
>({
  required List<TrayMenuEntry<TIcon>> entries,
  required Map<TIcon, TImage> menuImages,
  required void Function() addSeparator,
  required TItem? Function(String label) createItem,
  required void Function(TItem item, bool enabled) setEnabled,
  required void Function(TItem item, String id) attachClickListener,
  required void Function(TItem item) addItemToMenu,
  required void Function(TItem item, TImage image) setItemIcon,
  required List<TItem> outItems,
  required List<TIcon?> outItemIcons,
  required List<String?> outIds,
}) {
  for (final entry in entries) {
    switch (entry) {
      case TrayMenuSeparatorEntry():
        addSeparator();
        outIds.add(null);
      case TrayMenuItemEntry():
        final item = createItem(entry.label);
        if (item == null) continue;
        setEnabled(item, entry.enabled);
        final id = entry.id;
        attachClickListener(item, id);
        addItemToMenu(item);
        final menuIcon = entry.icon != null ? menuImages[entry.icon!] : null;
        if (menuIcon != null) {
          setItemIcon(item, menuIcon);
        }
        outItems.add(item);
        outItemIcons.add(entry.icon);
        outIds.add(id);
    }
  }
}

/// Resolves the platform-standard [ContextMenuTrigger] for each desktop OS.
ContextMenuTrigger? resolveTrayContextMenuTrigger({
  required bool isWindows,
  required bool isMacOS,
  required bool isLinux,
}) {
  if (isWindows || isLinux) {
    return ContextMenuTrigger.rightClicked;
  }
  if (isMacOS) {
    return ContextMenuTrigger.clicked;
  }
  return null;
}

/// Returns whether a Linux tray icon double-click event should toggle the
/// window after suppressing duplicate activation within [suppressionWindow].
bool shouldHandleLinuxDoubleClick({
  required DateTime? lastSingleClickAt,
  required DateTime now,
  Duration suppressionWindow = const Duration(milliseconds: 500),
}) {
  if (lastSingleClickAt == null) return true;
  return now.difference(lastSingleClickAt) >= suppressionWindow;
}
