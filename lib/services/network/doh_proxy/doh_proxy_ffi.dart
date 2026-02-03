import 'package:flutter/foundation.dart';

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// DOH Proxy FFI bindings
///
/// This provides direct FFI bindings to the Rust DOH proxy library
/// for Android and iOS platforms.
class DohProxyFfi {
  DohProxyFfi._();
  static final DohProxyFfi instance = DohProxyFfi._();

  DynamicLibrary? _lib;
  bool _initialized = false;

  // FFI function types
  late final int Function(int port, int preferIpv6) _dohProxyStart;
  late final int Function(int port, int preferIpv6, Pointer<Utf8> dohServer)
      _dohProxyStartWithServer;
  late final void Function() _dohProxyStop;
  late final int Function() _dohProxyIsRunning;
  late final int Function() _dohProxyGetPort;
  late final void Function() _dohProxyInitLogging;

  /// Initialize FFI bindings
  bool initialize() {
    if (_initialized) return true;

    try {
      _lib = _loadLibrary();
      if (_lib == null) return false;

      // Load function pointers
      _dohProxyStart = _lib!
          .lookup<NativeFunction<Int32 Function(Int32, Int32)>>(
              'doh_proxy_start')
          .asFunction();

      _dohProxyStartWithServer = _lib!
          .lookup<NativeFunction<Int32 Function(Int32, Int32, Pointer<Utf8>)>>(
              'doh_proxy_start_with_server')
          .asFunction();

      _dohProxyStop = _lib!
          .lookup<NativeFunction<Void Function()>>('doh_proxy_stop')
          .asFunction();

      _dohProxyIsRunning = _lib!
          .lookup<NativeFunction<Int32 Function()>>('doh_proxy_is_running')
          .asFunction();

      _dohProxyGetPort = _lib!
          .lookup<NativeFunction<Int32 Function()>>('doh_proxy_get_port')
          .asFunction();

      _dohProxyInitLogging = _lib!
          .lookup<NativeFunction<Void Function()>>('doh_proxy_init_logging')
          .asFunction();

      _initialized = true;
      return true;
    } catch (e) {
      debugPrint('[DOH FFI] Failed to initialize: $e');
      return false;
    }
  }

  DynamicLibrary? _loadLibrary() {
    try {
      if (Platform.isAndroid) {
        return DynamicLibrary.open('libdoh_proxy.so');
      } else if (Platform.isIOS) {
        // iOS uses static linking, so we use the process itself
        return DynamicLibrary.process();
      } else if (Platform.isWindows) {
        return DynamicLibrary.open('doh_proxy.dll');
      } else if (Platform.isMacOS) {
        return DynamicLibrary.open('libdoh_proxy.dylib');
      } else if (Platform.isLinux) {
        return DynamicLibrary.open('libdoh_proxy.so');
      }
    } catch (e) {
      debugPrint('[DOH FFI] Failed to load library: $e');
    }
    return null;
  }

  /// Start the DOH proxy server
  /// Returns the port number on success, or -1 on failure
  ///
  /// [port] - Port to bind (0 for auto-select)
  /// [preferIpv6] - Whether to prefer IPv6 addresses
  /// [dohServer] - DOH server URL (null for default Cloudflare)
  int start({int port = 0, bool preferIpv6 = false, String? dohServer}) {
    if (!_initialized && !initialize()) {
      return -1;
    }

    if (dohServer != null && dohServer.isNotEmpty) {
      // Use the new API with DOH server
      final dohServerPtr = dohServer.toNativeUtf8();
      try {
        return _dohProxyStartWithServer(port, preferIpv6 ? 1 : 0, dohServerPtr);
      } finally {
        calloc.free(dohServerPtr);
      }
    } else {
      // Use the legacy API (defaults to Cloudflare)
      return _dohProxyStart(port, preferIpv6 ? 1 : 0);
    }
  }

  /// Stop the DOH proxy server
  void stop() {
    if (!_initialized) return;
    _dohProxyStop();
  }

  /// Check if the DOH proxy is running
  bool isRunning() {
    if (!_initialized) return false;
    return _dohProxyIsRunning() != 0;
  }

  /// Get the DOH proxy port
  int getPort() {
    if (!_initialized) return 0;
    return _dohProxyGetPort();
  }

  /// Initialize logging
  void initLogging() {
    if (!_initialized && !initialize()) return;
    _dohProxyInitLogging();
  }

  /// Check if FFI is available on this platform
  static bool get isAvailable {
    return Platform.isAndroid || Platform.isIOS;
  }
}

/// Backwards compatibility alias
@Deprecated('Use DohProxyFfi instead')
typedef EchProxyFfi = DohProxyFfi;
