import 'dart:convert';
import 'dart:io';

import 'network/doh/network_settings_service.dart';
import 'package:path_provider/path_provider.dart';

/// CF 验证日志服务
/// 记录 Cloudflare 验证相关的详细信息，便于诊断问题
class CfChallengeLogger {
  static CfChallengeLogger? _instance;
  static File? _logFile;
  static bool _initialized = false;

  factory CfChallengeLogger() {
    _instance ??= CfChallengeLogger._();
    return _instance!;
  }

  CfChallengeLogger._();

  /// 初始化日志文件
  static Future<void> init() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${dir.path}/logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      _logFile = File('${logDir.path}/cf_challenge.log');
      // 清空旧日志（避免日志文件过大）
      if (await _logFile!.exists()) {
        final stat = await _logFile!.stat();
        // 如果日志文件超过 1MB，清空
        if (stat.size > 1024 * 1024) {
          await _logFile!.writeAsString('');
        }
      }
      _initialized = true;
      await log('=== CF Challenge Log Started ===');
    } catch (e) {
      // 忽略初始化错误
    }
  }

  /// 写入日志
  static Future<void> log(String message) async {
    if (!_initialized || _logFile == null) return;
    try {
      final timestamp = DateTime.now().toIso8601String();
      await _logFile!.writeAsString(
        '[$timestamp] $message\n',
        mode: FileMode.append,
      );
    } catch (e) {
      // 忽略写入错误
    }
  }

  /// 记录 Cookie 同步详情
  static Future<void> logCookieSync({
    required String direction,
    required List<CookieLogEntry> cookies,
  }) async {
    await log('[COOKIE] $direction - ${cookies.length} cookies');
    for (final cookie in cookies) {
      await log('  - ${cookie.name}: domain=${cookie.domain}, path=${cookie.path}, expires=${cookie.expires}, valueLen=${cookie.valueLength}');
    }
  }

  /// 记录验证开始
  static Future<void> logVerifyStart(String url) async {
    await log('[VERIFY] Start manual verify, url=$url');
  }

  /// 记录客户端/服务端 IP（用于 CF 验证诊断）
  static Future<void> logAccessIps({
    required String url,
    String? context,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      await log('[IP]${_formatContext(context)} host=unknown');
      return;
    }

    final host = uri.host;
    final clientIp = await _fetchClientIp(uri);
    final serverIps = await _resolveServerIps(host);
    final clientText = (clientIp == null || clientIp.isEmpty) ? 'unknown' : clientIp;
    final serverText = serverIps.isEmpty ? 'unknown' : serverIps.join(', ');

    await log('[IP]${_formatContext(context)} host=$host client=$clientText server=$serverText');
  }

  /// 记录验证检查
  static Future<void> logVerifyCheck({
    required int checkCount,
    required bool isChallenge,
    String? cfClearance,
    bool clearanceChanged = false,
  }) async {
    await log('[VERIFY] Check #$checkCount: isChallenge=$isChallenge, hasClearance=${cfClearance != null}, clearanceChanged=$clearanceChanged');
  }

  /// 记录验证结果
  static Future<void> logVerifyResult({
    required bool success,
    String? reason,
  }) async {
    if (success) {
      await log('[VERIFY] Result: SUCCESS${reason != null ? ' ($reason)' : ''}');
    } else {
      await log('[VERIFY] Result: FAILED${reason != null ? ' ($reason)' : ''}');
    }
  }

  /// 记录拦截器检测到 CF 验证
  static Future<void> logInterceptorDetected({
    required String url,
    required int statusCode,
  }) async {
    await log('[INTERCEPTOR] CF challenge detected: $statusCode $url');
  }

  /// 记录拦截器重试
  static Future<void> logInterceptorRetry({
    required String url,
    required bool success,
    int? statusCode,
    String? error,
  }) async {
    if (success) {
      await log('[INTERCEPTOR] Retry success: $statusCode $url');
    } else {
      await log('[INTERCEPTOR] Retry failed: $url, error=$error');
    }
  }

  /// 记录冷却期状态
  static Future<void> logCooldown({
    required bool entering,
    DateTime? until,
  }) async {
    if (entering) {
      await log('[COOLDOWN] Entering cooldown until $until');
    } else {
      await log('[COOLDOWN] Cooldown reset');
    }
  }

  /// 获取日志文件路径
  static Future<String?> getLogPath() async {
    if (_logFile == null) return null;
    return _logFile!.path;
  }

  /// 读取日志内容
  static Future<String?> readLogs() async {
    if (_logFile == null || !await _logFile!.exists()) return null;
    return _logFile!.readAsString();
  }

  /// 清除日志
  static Future<void> clear() async {
    if (_logFile == null) return;
    try {
      if (await _logFile!.exists()) {
        await _logFile!.writeAsString('');
      }
      await log('=== CF Challenge Log Cleared ===');
    } catch (e) {
      // 忽略清除错误
    }
  }

  static String _formatContext(String? context) {
    if (context == null || context.isEmpty) return '';
    return ' $context';
  }

  static Future<List<String>> _resolveServerIps(String host) async {
    if (host.isEmpty) return const [];
    final parsed = InternetAddress.tryParse(host);
    if (parsed != null) return [parsed.address];

    try {
      final resolver = NetworkSettingsService.instance.resolver;
      final addresses = await resolver.resolveAll(host);
      if (addresses.isNotEmpty) {
        return addresses.map((a) => a.address).toList();
      }
    } catch (_) {}

    try {
      final addresses = await InternetAddress.lookup(host);
      return addresses.map((a) => a.address).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<String?> _fetchClientIp(Uri baseUri) async {
    final traceUri = baseUri.replace(path: '/cdn-cgi/trace', query: '');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(traceUri);
      request.followRedirects = true;
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final body = await utf8.decodeStream(response);
      for (final line in body.split('\n')) {
        if (line.startsWith('ip=')) {
          return line.substring(3).trim();
        }
      }
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
    return null;
  }
}

/// Cookie 日志条目
class CookieLogEntry {
  final String name;
  final String? domain;
  final String? path;
  final DateTime? expires;
  final int valueLength;

  CookieLogEntry({
    required this.name,
    this.domain,
    this.path,
    this.expires,
    required this.valueLength,
  });
}
