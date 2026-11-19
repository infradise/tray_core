import 'dart:convert' show Utf8Codec;
import 'dart:ffi' as ffi;

/// Shared C heap allocation and string marshaling helpers for `tray_core`.
abstract final class TrayNativeMemory {
  /// Permissive UTF-8 codec that replaces malformed UTF-16 surrogates with
  /// U+FFFD rather than throwing or producing invalid UTF-8 byte sequences.
  static const Utf8Codec utf8Codec = Utf8Codec(allowMalformed: true);

  static final ffi.DynamicLibrary _processLib = ffi.DynamicLibrary.process();

  /// Allocates `byteCount` raw bytes on the native C heap.
  static final ffi.Pointer<ffi.Void> Function(int byteCount) malloc =
      _processLib.lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.Size),
        ffi.Pointer<ffi.Void> Function(int)
      >('malloc');

  /// Frees a native C heap pointer previously allocated by [malloc].
  static final void Function(ffi.Pointer<ffi.Void> pointer) free = _processLib
      .lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.Void>),
        void Function(ffi.Pointer<ffi.Void>)
      >('free');

  /// Fills [byteCount] bytes starting at [ptr] with zeroes.
  static void zeroFill(ffi.Pointer<ffi.Void> ptr, int byteCount) {
    if (ptr == ffi.nullptr || byteCount <= 0) return;
    final bytes = ptr.cast<ffi.Uint8>();
    for (var i = 0; i < byteCount; i++) {
      bytes[i] = 0;
    }
  }

  /// Encodes [value] as a NUL-terminated UTF-8 C string (`Pointer<Char>`) and
  /// frees the buffer when [action] completes.
  static T withUtf8<T>(
    String value,
    T Function(ffi.Pointer<ffi.Char> cstr) action,
  ) {
    final sanitized =
        value.contains('\u0000') ? value.replaceAll('\u0000', '') : value;
    final bytes = utf8Codec.encode(sanitized);
    final ptr = malloc(bytes.length + 1).cast<ffi.Uint8>();
    if (ptr == ffi.nullptr) {
      throw StateError(
        'malloc failed for UTF-8 C string (${bytes.length + 1}B)',
      );
    }
    try {
      for (var i = 0; i < bytes.length; i++) {
        ptr[i] = bytes[i];
      }
      ptr[bytes.length] = 0;
      return action(ptr.cast<ffi.Char>());
    } finally {
      free(ptr.cast());
    }
  }

  /// Encodes [value] as a NUL-terminated UTF-16LE wide string
  /// (`Pointer<Uint16>`) and frees the buffer when [action] completes.
  static T withUtf16<T>(
    String value,
    T Function(ffi.Pointer<ffi.Uint16> wstr) action,
  ) {
    final sanitized =
        value.contains('\u0000') ? value.replaceAll('\u0000', '') : value;
    final units = sanitized.codeUnits;
    final ptr = malloc((units.length + 1) * 2).cast<ffi.Uint16>();
    if (ptr == ffi.nullptr) {
      throw StateError(
        'malloc failed for UTF-16 string (${units.length + 1} units)',
      );
    }
    try {
      for (var i = 0; i < units.length; i++) {
        ptr[i] = units[i];
      }
      ptr[units.length] = 0;
      return action(ptr);
    } finally {
      free(ptr.cast());
    }
  }
}

/// Encodes [value] as a NUL-terminated UTF-8 C string (replacing any embedded
/// NUL code units and malformed UTF-16 surrogates) for safe FFI calls such as
/// Objective-C `+[NSString stringWithUTF8String:]`.
T withNullTerminatedUtf8<T>(
  String value,
  T Function(ffi.Pointer<ffi.Char> cstr) action,
) => TrayNativeMemory.withUtf8(value, action);
