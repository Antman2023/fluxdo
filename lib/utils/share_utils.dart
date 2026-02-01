import '../constants.dart';

/// 分享链接工具类
class ShareUtils {
  /// 构建分享链接
  ///
  /// [path] 路径部分，如 `/t/topic/123` 或 `/u/username`
  /// [username] 当前用户名
  /// [anonymousShare] 是否匿名分享（不附带用户标识）
  static String buildShareUrl({
    required String path,
    String? username,
    required bool anonymousShare,
  }) {
    final base = '${AppConstants.baseUrl}$path';
    if (anonymousShare || username == null || username.isEmpty) {
      return base;
    }
    return '$base?u=$username';
  }
}
