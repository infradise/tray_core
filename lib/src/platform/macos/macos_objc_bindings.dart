import 'dart:ffi' as ffi;
import 'dart:io';

import '../../ffi/tray_native_memory.dart';

/// Native `NSSize` ABI layout (`double width, double height`).
final class NSSize extends ffi.Struct {
  /// Horizontal span in points.
  @ffi.Double()
  external double width;

  /// Vertical span in points.
  @ffi.Double()
  external double height;
}

/// One-time cached Objective-C runtime and AppKit symbol + selector table for
/// `tray_core` on macOS.
class MacOSTrayObjCBindings {
  MacOSTrayObjCBindings._({
    required this.getClassPtr,
    required this.registerNamePtr,
    required this.objectGetClass,
    required this.classGetInstanceMethod,
    required this.allocateClassPair,
    required this.registerClassPair,
    required this.addMethod,
    required this.replaceMethod,
    required this.sendId,
    required this.sendId1,
    required this.sendIdDouble,
    required this.sendIdInitItem,
    required this.sendVoid,
    required this.sendVoidId,
    required this.sendVoidBool,
    required this.sendVoidInt,
    required this.sendVoidSize,
    required this.sendInt,
    required this.scratchSize,
  });

  static MacOSTrayObjCBindings? _instance;
  static bool _attempted = false;

  /// Returns the cached [MacOSTrayObjCBindings] singleton on macOS, or `null`
  /// on other OSes.
  static MacOSTrayObjCBindings? get instance {
    if (!Platform.isMacOS) return null;
    if (_attempted) return _instance;
    _attempted = true;

    try {
      try {
        ffi.DynamicLibrary.open(
          '/System/Library/Frameworks/AppKit.framework/AppKit',
        );
      } catch (_) {
        // AppKit may already be linked into the host Flutter runner.
      }
      final objc = ffi.DynamicLibrary.open('/usr/lib/libobjc.A.dylib');
      final msgSend = objc.lookup<ffi.NativeFunction<ffi.Void Function()>>(
        'objc_msgSend',
      );
      final sendVoidSizeFn =
          msgSend
              .cast<
                ffi.NativeFunction<
                  ffi.Void Function(
                    ffi.Pointer<ffi.Void>,
                    ffi.Pointer<ffi.Void>,
                    NSSize,
                  )
                >
              >()
              .asFunction<
                void Function(
                  ffi.Pointer<ffi.Void>,
                  ffi.Pointer<ffi.Void>,
                  NSSize,
                )
              >();

      final scratchSize =
          TrayNativeMemory.malloc(ffi.sizeOf<NSSize>()).cast<NSSize>();
      if (scratchSize == ffi.nullptr) return null;

      return _instance = MacOSTrayObjCBindings._(
        getClassPtr: objc.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>)
        >('objc_getClass'),
        registerNamePtr: objc.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>)
        >('sel_registerName'),
        objectGetClass: objc.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>),
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)
        >('object_getClass'),
        classGetInstanceMethod: objc.lookupFunction<
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
          ),
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
          )
        >('class_getInstanceMethod'),
        allocateClassPair: objc.lookupFunction<
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Char>,
            ffi.Size,
          ),
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Char>,
            int,
          )
        >('objc_allocateClassPair'),
        registerClassPair: objc.lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>),
          void Function(ffi.Pointer<ffi.Void>)
        >('objc_registerClassPair'),
        addMethod: objc.lookupFunction<
          ffi.Bool Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Char>,
          ),
          bool Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Char>,
          )
        >('class_addMethod'),
        replaceMethod: objc.lookupFunction<
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Char>,
          ),
          ffi.Pointer<ffi.Void> Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Char>,
          )
        >('class_replaceMethod'),
        sendId:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.Pointer<ffi.Void> Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                    )
                  >
                >()
                .asFunction(),
        sendId1:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.Pointer<ffi.Void> Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                    )
                  >
                >()
                .asFunction(),
        sendIdDouble:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.Pointer<ffi.Void> Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.Double,
                    )
                  >
                >()
                .asFunction(),
        sendIdInitItem:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.Pointer<ffi.Void> Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                    )
                  >
                >()
                .asFunction(),
        sendVoid:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.Void Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                    )
                  >
                >()
                .asFunction(),
        sendVoidId:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.Void Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                    )
                  >
                >()
                .asFunction(),
        sendVoidBool:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.Void Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.Bool,
                    )
                  >
                >()
                .asFunction(),
        sendVoidInt:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.Void Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                      ffi.IntPtr,
                    )
                  >
                >()
                .asFunction(),
        sendVoidSize: (target, selector, w, h) {
          scratchSize.ref
            ..width = w
            ..height = h;
          sendVoidSizeFn(target, selector, scratchSize.ref);
        },
        sendInt:
            msgSend
                .cast<
                  ffi.NativeFunction<
                    ffi.IntPtr Function(
                      ffi.Pointer<ffi.Void>,
                      ffi.Pointer<ffi.Void>,
                    )
                  >
                >()
                .asFunction(),
        scratchSize: scratchSize,
      );
    } catch (_) {
      return null;
    }
  }

  /// `objc_getClass`.
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>) getClassPtr;

  /// `sel_registerName`.
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>) registerNamePtr;

  /// `object_getClass`.
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>) objectGetClass;

  /// `class_getInstanceMethod`.
  final ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
  )
  classGetInstanceMethod;

  /// `objc_allocateClassPair`.
  final ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Char>,
    int,
  )
  allocateClassPair;

  /// `objc_registerClassPair`.
  final void Function(ffi.Pointer<ffi.Void>) registerClassPair;

  /// `class_addMethod`.
  final bool Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Char>,
  )
  addMethod;

  /// `class_replaceMethod`.
  final ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Char>,
  )
  replaceMethod;

  /// `id (*objc_msgSend)(id, SEL)`.
  final ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
  )
  sendId;

  /// `id (*objc_msgSend)(id, SEL, id)`.
  final ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
  )
  sendId1;

  /// `id (*objc_msgSend)(id, SEL, CGFloat)`.
  final ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    double,
  )
  sendIdDouble;

  /// `id (*objc_msgSend)(id, SEL, NSString*, SEL, NSString*)`.
  final ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
  )
  sendIdInitItem;

  /// `void (*objc_msgSend)(id, SEL)`.
  final void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>) sendVoid;

  /// `void (*objc_msgSend)(id, SEL, id)`.
  final void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
  )
  sendVoidId;

  /// `void (*objc_msgSend)(id, SEL, BOOL)`.
  final void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, bool)
  sendVoidBool;

  /// `void (*objc_msgSend)(id, SEL, NSInteger)`.
  final void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, int)
  sendVoidInt;

  /// `void (*objc_msgSend)(id, SEL, NSSize)`.
  final void Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    double,
    double,
  )
  sendVoidSize;

  /// `NSInteger (*objc_msgSend)(id, SEL)`.
  final int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>) sendInt;

  /// Reusable `NSSize` scratch buffer on the main UI thread.
  final ffi.Pointer<NSSize> scratchSize;

  final Map<String, ffi.Pointer<ffi.Void>> _classes =
      <String, ffi.Pointer<ffi.Void>>{};
  final Map<String, ffi.Pointer<ffi.Void>> _selectors =
      <String, ffi.Pointer<ffi.Void>>{};

  ffi.Pointer<ffi.Void>? _targetInstance;
  ffi.NativeCallable<
    ffi.Void Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
    )
  >?
  _menuClickCallable;

  final Map<int, void Function()> _menuActionsByTag = <int, void Function()>{};

  /// Looks up and caches an Objective-C `Class` pointer by [name].
  ffi.Pointer<ffi.Void> getClass(String name) {
    final cached = _classes[name];
    if (cached != null) return cached;
    final resolved = TrayNativeMemory.withUtf8(name, getClassPtr);
    if (resolved != ffi.nullptr) {
      _classes[name] = resolved;
    }
    return resolved;
  }

  /// Registers and caches an Objective-C `SEL` pointer by [name].
  ffi.Pointer<ffi.Void> sel(String name) {
    return _selectors.putIfAbsent(
      name,
      () => TrayNativeMemory.withUtf8(name, registerNamePtr),
    );
  }

  /// Converts [value] into a non-null `NSString*`, falling back to `@""` so
  /// AppKit `nonnull NSString*` assertions never trip on malformed strings.
  ffi.Pointer<ffi.Void> nsString(String value) {
    final cls = getClass('NSString');
    if (cls == ffi.nullptr) return ffi.nullptr;
    final created = TrayNativeMemory.withUtf8(
      value,
      (cstr) => sendId1(cls, sel('stringWithUTF8String:'), cstr.cast()),
    );
    if (created != ffi.nullptr) return created;
    return sendId(cls, sel('string'));
  }

  /// Reads an `NSString*` back into a Dart `String` via `UTF8String`.
  String? dartStringFromNSString(ffi.Pointer<ffi.Void> nsStr) {
    if (nsStr == ffi.nullptr) return null;
    final utf8Ptr = sendId(nsStr, sel('UTF8String')).cast<ffi.Uint8>();
    if (utf8Ptr == ffi.nullptr) return null;
    var len = 0;
    while (utf8Ptr[len] != 0) {
      len++;
    }
    final bytes = <int>[for (var i = 0; i < len; i++) utf8Ptr[i]];
    return TrayNativeMemory.utf8Codec.decode(bytes);
  }

  /// Registers [callback] for `NSMenuItem.tag == [tag]`.
  void registerMenuAction(int tag, void Function() callback) {
    _menuActionsByTag[tag] = callback;
  }

  /// Unregisters any action associated with `NSMenuItem.tag == [tag]`.
  void unregisterMenuAction(int tag) {
    _menuActionsByTag.remove(tag);
  }

  /// Lazily allocates and returns the singleton Objective-C
  /// `TrayCoreMenuTarget` instance receiving `onTrayMenuItemClicked:`.
  ffi.Pointer<ffi.Void> ensureMenuTarget() {
    final existing = _targetInstance;
    if (existing != null && existing != ffi.nullptr) return existing;

    _menuClickCallable ??= ffi.NativeCallable<
      ffi.Void Function(
        ffi.Pointer<ffi.Void>,
        ffi.Pointer<ffi.Void>,
        ffi.Pointer<ffi.Void>,
      )
    >.isolateLocal(_handleMenuClick);

    var targetCls = getClass('TrayCoreMenuTarget');
    final actionSel = sel('onTrayMenuItemClicked:');
    if (targetCls == ffi.nullptr) {
      final nsObject = getClass('NSObject');
      targetCls = TrayNativeMemory.withUtf8(
        'TrayCoreMenuTarget',
        (name) => allocateClassPair(nsObject, name, 0),
      );
      TrayNativeMemory.withUtf8('v@:@', (types) {
        addMethod(
          targetCls,
          actionSel,
          _menuClickCallable!.nativeFunction.cast(),
          types,
        );
      });
      registerClassPair(targetCls);
    } else {
      // Across Flutter Hot Restart, the Objective-C runtime retains the
      // previously registered `TrayCoreMenuTarget` class whose IMP points at
      // the terminated isolate's trampoline. Rebind it to this live isolate.
      TrayNativeMemory.withUtf8('v@:@', (types) {
        replaceMethod(
          targetCls,
          actionSel,
          _menuClickCallable!.nativeFunction.cast(),
          types,
        );
      });
    }

    return _targetInstance = sendId(
      sendId(targetCls, sel('alloc')),
      sel('init'),
    );
  }

  static void _handleMenuClick(
    ffi.Pointer<ffi.Void> self,
    ffi.Pointer<ffi.Void> cmd,
    ffi.Pointer<ffi.Void> sender,
  ) {
    final objc = instance;
    if (objc == null || sender == ffi.nullptr) return;
    final tag = objc.sendInt(sender, objc.sel('tag'));
    objc._menuActionsByTag[tag]?.call();
  }
}
