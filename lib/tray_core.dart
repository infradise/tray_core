/// Pure-Dart and FFI cross-platform desktop system tray and popup menu engine
/// for Flutter across Linux (`StatusNotifierItem` + `DBusMenu`), macOS
/// (`NSStatusItem` + `NSMenu`), and Windows (`Shell_NotifyIconW` + 32-bit DIB
/// `HBITMAP`).
library;

export 'src/native_tray_backend.dart' show NativeTrayBackend;
export 'src/platform/linux/linux_dbusmenu_object.dart'
    show DbusMenuStateMachine, DbusMenuUpdateDelta, TrayDbusMenuObject;
export 'src/platform/linux/linux_sni_tray_backend.dart'
    show LinuxDbusTrayBackend, LinuxSniTrayBackend, decodePngToSniIconPixmap;
export 'src/platform/linux/linux_tray_environment.dart'
    show
        GnomeTrayRemediationResult,
        LinuxTrayReport,
        LinuxTrayWatcherSubscription,
        LinuxWatcherSubscriber,
        activateStatusNotifierWatcherViaDBus,
        buildCleanTrayHostEnvironment,
        checkLinuxTraySupport,
        ensureGnomeTrayExtensionEnabled,
        evaluateLinuxTrayEnvironment,
        installAndEnableLinuxGnomeTray,
        isGnomeDesktopEnvironment,
        kDefaultGnomeAppIndicatorUuid,
        linuxGnomeTrayExtensionUuids,
        linuxStatusNotifierWatcherNames,
        openLinuxSessionBus,
        probeStatusNotifierWatcher,
        subscribeStatusNotifierWatcherChanges,
        waitForStatusNotifierWatcher;
export 'src/platform/macos/macos_menu_visibility.dart'
    show
        getMacOSMenuItemImageVisibility,
        kNSMenuItemImageVisibilityAutomatic,
        kNSMenuItemImageVisibilityHidden,
        kNSMenuItemImageVisibilityVisible,
        setMacOSMenuItemImageVisibility;
export 'src/platform/macos/macos_tray_backend.dart'
    show MacOSStatusItemTrayBackend, MacOSTrayBackend;
export 'src/platform/windows/windows_tray_backend.dart'
    show WindowsTrayBackend, WindowsWin32TrayBackend;
export 'src/tray_backend.dart' show TrayBackend;
export 'src/tray_icon_resolver.dart'
    show
        TrayIconResolver,
        kTrayIconIcoAsset,
        kTrayIconPngAsset,
        trayIconAssetFor;
export 'src/tray_menu_entry.dart'
    show
        ContextMenuTrigger,
        ResolvedTrayMenuIcon,
        TrayMenuEntry,
        TrayMenuItemEntry,
        TrayMenuSeparatorEntry,
        populateNativeTrayMenuEntries,
        resolveTrayContextMenuTrigger,
        shouldHandleLinuxDoubleClick,
        trayMenuSignature;
