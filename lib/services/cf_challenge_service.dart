import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../constants.dart';
import 'network/cookie/cookie_jar_service.dart';
import 'local_notification_service.dart'; // 用于获取全局 navigatorKey
import 'cf_challenge_logger.dart';
import '../widgets/draggable_floating_pill.dart';

/// CF 验证服务
/// 处理 Cloudflare Turnstile 验证（仅手动模式）
class CfChallengeService {
  static final CfChallengeService _instance = CfChallengeService._internal();
  factory CfChallengeService() => _instance;
  CfChallengeService._internal();

  bool _isVerifying = false;
  final _verifyCompleter = <Completer<bool>>[];
  BuildContext? _context;
  
  /// 冷却机制：验证失败后进入冷却期
  DateTime? _cooldownUntil;
  static const _cooldownDuration = Duration(seconds: 30);
  
  /// 检查是否在冷却期
  bool get isInCooldown {
    if (_cooldownUntil == null) return false;
    if (DateTime.now().isAfter(_cooldownUntil!)) {
      _cooldownUntil = null;
      return false;
    }
    return true;
  }
  
  /// 重置冷却期（验证成功后调用）
  void resetCooldown() {
    _cooldownUntil = null;
    CfChallengeLogger.logCooldown(entering: false);
  }

  /// 手动启动冷却期
  void startCooldown() {
    _cooldownUntil = DateTime.now().add(_cooldownDuration);
    CfChallengeLogger.logCooldown(entering: true, until: _cooldownUntil);
  }

  void setContext(BuildContext context) {
    _context = context;
  }

  /// 检测是否是 CF 验证页面
  static bool isCfChallenge(dynamic responseData) {
    if (responseData == null) return false;
    final str = responseData.toString();
    return str.contains('Just a moment') ||
           str.contains('cf_chl_opt') ||
           str.contains('challenge-platform');
  }

  /// 显示手动验证页面
  /// 返回值：true=验证成功, false=验证失败, null=冷却期内暂不可用或无 context
  Future<bool?> showManualVerify([BuildContext? context]) async {
    // 检查冷却期
    if (isInCooldown) {
      debugPrint('[CfChallenge] In cooldown, skipping manual verify');
      CfChallengeLogger.log('[VERIFY] Skipped: in cooldown');
      return null;
    }

    final verifyUrl = '${AppConstants.baseUrl}/challenge';
    CfChallengeLogger.logVerifyStart(verifyUrl);
    unawaited(CfChallengeLogger.logAccessIps(url: verifyUrl, context: 'verify_start'));
    
    // 尝试获取 context：传入的 > 已设置的 > 全局 navigatorKey
    BuildContext? ctx = context ?? _context;
    if (ctx == null) {
      // 使用全局 navigatorKey 作为备用
      final navState = navigatorKey.currentState;
      if (navState != null && navState.context.mounted) {
        ctx = navState.context;
        debugPrint('[CfChallenge] Using global navigatorKey context');
      }
    }
    
    if (ctx == null) {
      debugPrint('[CfChallenge] No context available for manual verify (context not set and navigatorKey not ready)');
      // 返回 null 而不是 false，让调用方知道这是"无法验证"而非"验证失败"
      return null;
    }

    if (_isVerifying) {
      // 已经在验证中，等待结果
      final completer = Completer<bool>();
      _verifyCompleter.add(completer);
      return completer.future;
    }

    _isVerifying = true;

    final overlayState = Overlay.maybeOf(ctx, rootOverlay: true);
    if (overlayState == null) {
      debugPrint('[CfChallenge] No overlay available for manual verify');
      CfChallengeLogger.log('[VERIFY] No overlay available');
      _isVerifying = false;
      return null;
    }

    // 打开 WebView 前先同步 Cookie 到 WebView
    await CookieJarService().syncToWebView();
    if (!overlayState.mounted) {
      debugPrint('[CfChallenge] Overlay no longer mounted');
      CfChallengeLogger.log('[VERIFY] Overlay not mounted');
      _isVerifying = false;
      return null;
    }

    final resultCompleter = Completer<bool>();
    late final OverlayEntry entry;
    void finish(bool success) {
      if (!resultCompleter.isCompleted) {
        resultCompleter.complete(success);
      }
      if (entry.mounted) {
        entry.remove();
      }
    }

    entry = OverlayEntry(
      builder: (_) => CfChallengePage(
        startInBackground: true,
        onResult: finish,
      ),
    );
    overlayState.insert(entry);

    final result = await resultCompleter.future;

    _isVerifying = false;

    // 通知所有等待者
    for (final c in _verifyCompleter) {
      if (!c.isCompleted) c.complete(result);
    }
    _verifyCompleter.clear();

    // 验证成功后重置冷却期
    // 注意：syncFromWebView 由拦截器调用，避免重复
    if (result == true) {
      resetCooldown();
      CfChallengeLogger.logVerifyResult(success: true, reason: 'user completed');
    } else {
      // 验证失败，启动冷却期
      startCooldown();
      debugPrint('[CfChallenge] Verification failed, cooldown until $_cooldownUntil');
      CfChallengeLogger.logVerifyResult(success: false, reason: 'user cancelled or timeout');
    }

    return result;
  }
}

/// CF 验证页面
class CfChallengePage extends StatefulWidget {
  const CfChallengePage({
    super.key,
    this.startInBackground = false,
    this.onResult,
  });

  /// 先后台尝试验证，超时后再切到前台
  final bool startInBackground;
  final ValueChanged<bool>? onResult;

  @override
  State<CfChallengePage> createState() => _CfChallengePageState();
}

class _CfChallengePageState extends State<CfChallengePage> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  double _progress = 0;
  Timer? _checkTimer;
  String? _initialCfClearance;
  bool _navigatedAfterClearance = false;
  bool _hasPopped = false; // 防止重复 pop
  late bool _isBackground;
  int _checkCount = 0;
  static const _backgroundMaxCheckCount = 10;
  static const _foregroundMaxCheckCount = 60;

  int get _activeMaxCheckCount =>
      _isBackground ? _backgroundMaxCheckCount : _foregroundMaxCheckCount;

  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showUi = !_isBackground;

    return Stack(
      children: [
        // 内容层：显示 WebView UI
        // 当后台可交互时(_isBackground==false)，正常显示 Scaffold
        // 当后台不可交互时(_isBackground==true)，Scaffold 应该是完全透明且不响应点击
        IgnorePointer(
          ignoring: _isBackground,
          child: Opacity(
            opacity: _isBackground ? 0 : 1,
            child: Scaffold(
              backgroundColor: Colors.transparent, // 始终透明，依靠内容决定是否遮挡
              appBar: showUi
                  ? AppBar(
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('安全验证'),
                          if (_checkCount > 0)
                            Text(
                              '验证中... ${_checkCount}s',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      leading: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => _finish(false),
                      ),
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _refresh,
                          tooltip: '刷新',
                        ),
                        IconButton(
                          icon: const Icon(Icons.help_outline),
                          onPressed: _showHelp,
                          tooltip: '帮助',
                        ),
                      ],
                    )
                  : null,
              body: Column(
                children: [
                  if (showUi && _isLoading)
                    LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        // WebView
                        // 仅在后台时忽略 WebView 的点击
                        IgnorePointer(
                          ignoring: _isBackground,
                          child: InAppWebView(
                            initialUrlRequest: URLRequest(
                                url: WebUri('${AppConstants.baseUrl}/challenge')),
                            initialSettings: InAppWebViewSettings(
                              javaScriptEnabled: true,
                              userAgent: AppConstants.userAgent,
                              mediaPlaybackRequiresUserGesture: false,
                            ),
                            onWebViewCreated: (controller) =>
                                _controller = controller,
                            onLoadStart: (controller, url) {
                              setState(() {
                                _isLoading = true;
                                _progress = 0;
                              });
                              _startVerifyCheck(controller, restart: false);
                            },
                            onProgressChanged: (controller, progress) {
                              _progress = progress / 100;
                              if (showUi) {
                                setState(() {});
                              }
                            },
                            onLoadStop: (controller, url) {
                              if (mounted) {
                                setState(() => _isLoading = false);
                              }
                              _startVerifyCheck(controller);
                            },
                            onReceivedError: (controller, request, error) {
                              if (mounted) {
                                setState(() => _isLoading = false);
                              }
                              if (showUi) {
                                _showError('加载失败: ${error.description}');
                              }
                            },
                          ),
                        ),
                        
                        // 警告卡片 (位于 Inner Stack，仅在前台显示)
                        if (showUi &&
                            _checkCount > _activeMaxCheckCount - 10 &&
                            _checkCount <= _activeMaxCheckCount)
                          Positioned(
                            bottom: 16,
                            left: 16,
                            right: 16,
                            child: Card(
                              color: theme.colorScheme.errorContainer,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      color: theme.colorScheme.onErrorContainer,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '验证时间较长，还剩 ${_activeMaxCheckCount - _checkCount} 秒',
                                        style: TextStyle(
                                          color: theme.colorScheme.onErrorContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 悬浮验证胶囊 (位于 Outer Stack，仅在后台显示)
        if (_isBackground)
          DraggableFloatingPill(
            initialTop: 100,
            onTap: _promoteToForeground,
            child: const Text('后台验证中... (点击打开)'),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _isBackground = widget.startInBackground;
  }

  /// 启动定时检查验证状态（非阻塞）
  void _startVerifyCheck(
    InAppWebViewController controller, {
    bool restart = true,
  }) {
    if (!restart && (_checkTimer?.isActive ?? false)) {
      return;
    }
    _checkTimer?.cancel();
    _checkCount = 0;

    Future<String?> getCfClearance() async {
      final cookies = await CookieManager.instance().getCookies(url: WebUri(AppConstants.baseUrl));
      for (final cookie in cookies) {
        if (cookie.name == 'cf_clearance') return cookie.value;
      }
      return null;
    }

    _checkTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      _checkCount++;
      if (!_isBackground) {
        setState(() {}); // 更新计数显示
      }

      if (_checkCount > _activeMaxCheckCount) {
        if (_isBackground) {
          CfChallengeLogger.log(
              '[VERIFY] Background timeout after $_activeMaxCheckCount seconds, prompting manual verify');
          // 超时后调用 promoteToForeground 切到前台
          _promoteToForeground();
          return;
        }
        timer.cancel();
        CfChallengeLogger.logVerifyResult(success: false, reason: 'timeout after $_activeMaxCheckCount seconds');
        if (mounted) {
          _showError('验证超时，请重试');
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            _finish(false);
          }
        }
        return;
      }

      try {
        _initialCfClearance ??= await getCfClearance();
        final html = await controller.evaluateJavascript(source: 'document.body.innerHTML');
        final isChallenge = CfChallengeService.isCfChallenge(html);
        final currentCfClearance = await getCfClearance();
        final clearanceChanged = currentCfClearance != null &&
            currentCfClearance.isNotEmpty &&
            (_initialCfClearance == null || currentCfClearance != _initialCfClearance);

        debugPrint('[CfChallenge] tick#$_checkCount isChallenge=$isChallenge hasClearance=${currentCfClearance != null}');
        CfChallengeLogger.logVerifyCheck(
          checkCount: _checkCount,
          isChallenge: isChallenge,
          cfClearance: currentCfClearance,
          clearanceChanged: clearanceChanged,
        );

        // 验证成功条件：HTML 不包含验证标记 且 cf_clearance Cookie 存在
        if (html != null && !isChallenge && currentCfClearance != null && currentCfClearance.isNotEmpty) {
          timer.cancel();
          CfChallengeLogger.logVerifyResult(success: true, reason: 'page loaded and cf_clearance present');
          if (mounted) {
            _finish(true);
          }
          return;
        }

        if (clearanceChanged) {
          debugPrint('[CfChallenge] clearance updated');
          if (!_navigatedAfterClearance) {
            _navigatedAfterClearance = true;
            debugPrint('[CfChallenge] navigating to baseUrl');
            await controller.loadUrl(
              urlRequest: URLRequest(url: WebUri(AppConstants.baseUrl)),
            );
            return;
          }
          // cf_clearance 已更新且已导航，确认验证成功
          timer.cancel();
          CfChallengeLogger.logVerifyResult(success: true, reason: 'clearance changed after navigation');
          if (mounted) {
            _finish(true);
          }
        }
      } catch (e) {
        debugPrint('[CfChallenge] Check error: $e');
        CfChallengeLogger.log('[VERIFY] Check error: $e');
      }
    });
  }

  void _refresh() {
    _checkTimer?.cancel();
    _checkCount = 0;
    _initialCfClearance = null;
    _navigatedAfterClearance = false;
    setState(() {
      _isLoading = true;
      _progress = 0;
    });
    _controller?.reload();
  }

  void _promoteToForeground() {
    if (!_isBackground) return;
    setState(() {
      _isBackground = false;
      _checkCount = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showInfo('自动验证超时，请手动完成验证');
    });
  }

  void _finish(bool success) {
    if (_hasPopped) return;
    _hasPopped = true;
    final handler = widget.onResult;
    if (handler != null) {
      handler(success);
    } else {
      Navigator.of(context).pop(success);
    }
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('验证帮助'),
        content: const Text(
          '这是 Cloudflare 安全验证页面。\n\n'
          '请完成页面上的验证挑战（如勾选框或滑块）。\n\n'
          '验证成功后会自动关闭此页面。\n\n'
          '如果长时间无法完成，可以尝试：\n'
          '• 点击刷新按钮重新加载\n'
          '• 检查网络连接\n'
          '• 关闭后稍后再试',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
