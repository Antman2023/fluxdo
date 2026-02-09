import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../pages/user_profile_page.dart';
import '../pages/webview_page.dart';
import '../providers/preferences_provider.dart';
import 'url_helper.dart';

const _browserChannel = MethodChannel('com.github.lingyan000.fluxdo/browser');

/// 检查 URL 是否属于站点内部链接（主域名或子域名）
bool isInternalUrl(Uri uri) {
  final baseUri = Uri.tryParse(AppConstants.baseUrl);
  if (baseUri == null) return false;

  final baseHost = baseUri.host; // 如 'linux.do'
  final host = uri.host;

  // 主域名或子域名
  return host == baseHost || host.endsWith('.$baseHost');
}

/// 检查 URL 是否属于站点内部链接（字符串版本，支持相对路径）
bool isInternalUrlString(String url) {
  if (url.startsWith('/')) return true;
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return isInternalUrl(uri);
}

/// 打开外部链接
///
/// 根据用户偏好决定使用内置浏览器还是外部浏览器
Future<void> launchExternalLink(BuildContext context, String url) async {
  if (url.isEmpty) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;

  final prefs =
      ProviderScope.containerOf(context, listen: false).read(preferencesProvider);
  final preferInApp = prefs.openExternalLinksInAppBrowser;

  if (preferInApp && (uri.scheme == 'http' || uri.scheme == 'https')) {
    WebViewPage.open(context, url);
    return;
  }

  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// 打开内容中的链接（统一入口）
///
/// 处理所有类型的链接：
/// - 用户链接 /u/username → 打开用户页面
/// - 话题链接 /t/topic/123 → 调用 onInternalLinkTap 或用 WebView 打开
/// - 附件链接 /uploads/ → 外部浏览器打开
/// - 站点内部链接（主域名或子域名）→ 内置浏览器
/// - Email 链接 → 外部邮件客户端
/// - 外部链接 → 根据用户偏好决定
Future<void> launchContentLink(
  BuildContext context,
  String url, {
  void Function(int topicId, String? topicSlug, int? postNumber)? onInternalLinkTap,
}) async {
  if (url.isEmpty) return;

  // 1. 识别用户链接 /u/username
  final userMatch = RegExp(r'/u/([^/?#]+)').firstMatch(url);
  if (userMatch != null && isInternalUrlString(url)) {
    final username = userMatch.group(1)!;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserProfilePage(username: username)),
    );
    return;
  }

  // 2. 解析话题链接 /t/topic/123
  final topicMatch = RegExp(r'/t/(?:[^/]+/)?(\d+)(?:/(\d+))?').firstMatch(url);
  if (topicMatch != null && isInternalUrlString(url)) {
    if (onInternalLinkTap != null) {
      final topicId = int.parse(topicMatch.group(1)!);
      final postNumber = int.tryParse(topicMatch.group(2) ?? '');
      final slugMatch = RegExp(r'/t/([^/]+)/\d+').firstMatch(url);
      final slug = (slugMatch != null && slugMatch.group(1) != 'topic')
          ? slugMatch.group(1)
          : null;
      onInternalLinkTap(topicId, slug, postNumber);
      return;
    }
    // 没有回调时用 WebView 打开
    final fullUrl = UrlHelper.resolveUrl(url);
    WebViewPage.open(context, fullUrl);
    return;
  }

  // 3. 下载附件链接：/uploads/ 路径用外部浏览器
  if (url.contains('/uploads/') && isInternalUrlString(url)) {
    final fullUrl = UrlHelper.resolveUrl(url);
    final uri = Uri.tryParse(fullUrl);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return;
  }

  // 4. Email 链接
  if (url.startsWith('mailto:')) {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return;
  }

  // 5. 站点内部链接（主域名或子域名、相对路径）→ 内置浏览器
  if (isInternalUrlString(url)) {
    final fullUrl = UrlHelper.resolveUrl(url);
    WebViewPage.open(context, fullUrl);
    return;
  }

  // 6. 外部链接 → 根据用户偏好决定
  await launchExternalLink(context, url);
}

/// 强制在外部浏览器打开链接，绕过 App Links
///
/// 在 Android 上通过原生代码排除自己的应用，直接用外部浏览器打开，
/// 避免被应用的 intent-filter 拦截导致链接又回到应用本身。
Future<bool> launchInExternalBrowser(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;

  if (Platform.isAndroid) {
    try {
      final result = await _browserChannel.invokeMethod<bool>(
        'openInBrowser',
        {'url': url},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('[LinkLauncher] Failed to launch browser: $e');
      // 回退到 url_launcher
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
      return false;
    }
  } else {
    // iOS 和其他平台使用 url_launcher
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }
    return false;
  }
}
