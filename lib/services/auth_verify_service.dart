import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import 'network/cookie/cookie_jar_service.dart';
import 'preloaded_data_service.dart';
import 'auth_log_service.dart';

/// WebView 登录验证服务
/// 通过无头 WebView 访问站点，检查 data-preloaded 中的 currentUser
/// 用于在触发登出前二次确认登录状态
class AuthVerifyService {
  static final AuthVerifyService _instance = AuthVerifyService._internal();
  factory AuthVerifyService() => _instance;
  AuthVerifyService._internal();

  static const String _enabledKey = 'auth_verify_enabled';
  
  bool _enabled = true;
  bool _isVerifying = false;
  DateTime? _lastVerifyTime;
  
  /// 最小验证间隔（防止频繁验证）
  static const _minVerifyInterval = Duration(seconds: 30);
  
  /// 验证超时时间
  static const _verifyTimeout = Duration(seconds: 15);

  /// 设置开关状态
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    debugPrint('[AuthVerifyService] 开关状态: $enabled');
  }

  /// 获取开关状态
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true;
    return _enabled;
  }

  /// 检查是否在冷却期
  bool get _isInCooldown {
    if (_lastVerifyTime == null) return false;
    return DateTime.now().difference(_lastVerifyTime!) < _minVerifyInterval;
  }

  /// 验证登录状态
  /// 返回: true=已登录, false=未登录, null=验证失败/跳过
  Future<bool?> verifyLoginStatus() async {
    // 检查开关
    if (!await isEnabled()) {
      debugPrint('[AuthVerifyService] 功能已禁用，跳过验证');
      return null;
    }

    // 检查是否正在验证或在冷却期
    if (_isVerifying) {
      debugPrint('[AuthVerifyService] 正在验证中，跳过');
      return null;
    }
    
    if (_isInCooldown) {
      debugPrint('[AuthVerifyService] 在冷却期内，跳过');
      return null;
    }

    _isVerifying = true;
    _lastVerifyTime = DateTime.now();

    try {
      debugPrint('[AuthVerifyService] 开始 WebView 验证...');
      
      // 同步当前 Cookie 到 WebView
      await CookieJarService().syncToWebView();
      
      // 使用无头 WebView 加载页面
      final result = await _loadAndVerify();
      
      if (result == true) {
        // 验证成功：同步 Cookie 回客户端
        await AuthLogService().logWebViewVerify(
          success: true,
          reason: 'currentUser_found',
        );
        await _syncCookiesToClient();
        debugPrint('[AuthVerifyService] 验证成功，已恢复登录');
      } else if (result == false) {
        await AuthLogService().logWebViewVerify(
          success: false,
          reason: 'currentUser_not_found',
        );
        debugPrint('[AuthVerifyService] 验证失败，确认已登出');
      } else {
        await AuthLogService().logWebViewVerify(
          success: false,
          reason: 'verify_error',
        );
        debugPrint('[AuthVerifyService] 验证过程出错');
      }
      
      return result;
    } catch (e) {
      debugPrint('[AuthVerifyService] 验证异常: $e');
      await AuthLogService().logWebViewVerify(
        success: false,
        reason: 'exception',
        extra: {'error': e.toString()},
      );
      return null;
    } finally {
      _isVerifying = false;
    }
  }

  /// 使用无头 WebView 加载页面并解析 currentUser
  Future<bool?> _loadAndVerify() async {
    final completer = Completer<bool?>();
    HeadlessInAppWebView? headlessWebView;
    Timer? timeoutTimer;

    try {
      headlessWebView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(AppConstants.baseUrl),
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          userAgent: AppConstants.userAgent,
        ),
        onLoadStop: (controller, url) async {
          if (completer.isCompleted) return;
          
          try {
            // 获取 HTML 内容
            final html = await controller.evaluateJavascript(
              source: 'document.documentElement.outerHTML',
            );
            
            if (html == null || html.isEmpty) {
              completer.complete(null);
              return;
            }
            
            // 解析 data-preloaded 中的 currentUser
            final hasCurrentUser = _parseCurrentUserFromHtml(html.toString());
            completer.complete(hasCurrentUser);
          } catch (e) {
            debugPrint('[AuthVerifyService] 解析页面失败: $e');
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          }
        },
        onReceivedError: (controller, request, error) {
          debugPrint('[AuthVerifyService] 加载失败: ${error.type} ${error.description}');
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        },
        onReceivedHttpError: (controller, request, response) {
          debugPrint('[AuthVerifyService] HTTP 错误: ${response.statusCode} ${response.reasonPhrase}');
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        },
      );

      // 设置超时
      timeoutTimer = Timer(_verifyTimeout, () {
        if (!completer.isCompleted) {
          debugPrint('[AuthVerifyService] 验证超时');
          completer.complete(null);
        }
      });

      await headlessWebView.run();
      return await completer.future;
    } finally {
      timeoutTimer?.cancel();
      await headlessWebView?.dispose();
    }
  }

  /// 从 HTML 中解析 data-preloaded 并检查 currentUser
  bool _parseCurrentUserFromHtml(String html) {
    try {
      // 提取 data-preloaded 属性内容
      final match = RegExp(r'data-preloaded="([^"]*)"').firstMatch(html);
      if (match == null) {
        debugPrint('[AuthVerifyService] 未找到 data-preloaded 属性');
        return false;
      }

      // 解码 HTML entities
      final decoded = match.group(1)!
          .replaceAll('&quot;', '"')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&#39;', "'");

      // 解析 JSON
      final preloaded = jsonDecode(decoded) as Map<String, dynamic>;
      
      // 检查是否有 currentUser
      if (preloaded.containsKey('currentUser')) {
        final currentUserJson = preloaded['currentUser'] as String;
        final currentUser = jsonDecode(currentUserJson) as Map<String, dynamic>;
        
        if (currentUser.containsKey('id') && currentUser['id'] != null) {
          debugPrint('[AuthVerifyService] 找到 currentUser: id=${currentUser['id']}');
          return true;
        }
      }
      
      debugPrint('[AuthVerifyService] 未找到有效的 currentUser');
      return false;
    } catch (e) {
      debugPrint('[AuthVerifyService] 解析 preloaded 数据失败: $e');
      return false;
    }
  }

  /// 同步 WebView Cookie 到客户端
  Future<void> _syncCookiesToClient() async {
    try {
      await CookieJarService().syncFromWebView();
      // 刷新预加载数据
      await PreloadedDataService().refresh();
      debugPrint('[AuthVerifyService] Cookie 同步完成');
    } catch (e) {
      debugPrint('[AuthVerifyService] Cookie 同步失败: $e');
    }
  }

  /// 重置冷却期（测试用途）
  void resetCooldown() {
    _lastVerifyTime = null;
  }
}
