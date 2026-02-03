import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Proxy CA certificate management
///
/// Configures the app to trust the MITM proxy's CA certificate
/// on all platforms.
class ProxyCertificate {
  ProxyCertificate._();

  static bool _initialized = false;

  /// Initialize the security context to trust the proxy CA
  ///
  /// Call this early in app startup (e.g., in main.dart)
  static Future<void> initialize() async {
    if (_initialized) return;

    // On Android, the CA is trusted via network_security_config.xml
    // On other platforms, we need to configure it programmatically
    if (!Platform.isAndroid) {
      await _configureSecurityContext();
    }

    _initialized = true;
  }

  /// Configure the global security context to trust the proxy CA
  static Future<void> _configureSecurityContext() async {
    try {
      // Load the CA certificate from assets
      final certData = await rootBundle.load('assets/certs/proxy_ca.pem');
      final certBytes = certData.buffer.asUint8List();

      // Get the global security context
      final context = SecurityContext.defaultContext;

      // Add the CA as a trusted certificate
      context.setTrustedCertificatesBytes(certBytes);

      // ignore: avoid_print
      debugPrint('ProxyCertificate: CA certificate loaded successfully');
    } catch (e) {
      // Certificate might already be trusted or file not found
      // This is not fatal - Android uses network_security_config
      // ignore: avoid_print
      debugPrint('ProxyCertificate: Could not load CA certificate: $e');
    }
  }

  /// Get the CA certificate PEM content for display or export
  static Future<String?> getCertificatePem() async {
    try {
      return await rootBundle.loadString('assets/certs/proxy_ca.pem');
    } catch (e) {
      return null;
    }
  }
}
