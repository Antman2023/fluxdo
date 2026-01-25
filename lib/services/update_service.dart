import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 更新信息模型
class UpdateInfo {
  final String currentVersion;
  final String remoteVersion;
  final String releaseUrl;
  final String releaseNotes;
  final bool hasUpdate;

  UpdateInfo({
    required this.currentVersion,
    required this.remoteVersion,
    required this.releaseUrl,
    required this.releaseNotes,
    required this.hasUpdate,
  });
}

/// 应用更新检查服务
class UpdateService {
  static const String _repository = 'Lingyan000/fluxdo';
  static const String _apiUrl = 'https://api.github.com/repos/$_repository/releases/latest';
  static const String _autoCheckUpdateKey = 'auto_check_update';

  final Dio _dio;
  final SharedPreferences? _prefs;

  UpdateService({Dio? dio, SharedPreferences? prefs})
      : _dio = dio ?? Dio(),
        _prefs = prefs;

  /// 获取自动检查更新设置
  bool getAutoCheckUpdate() {
    return _prefs?.getBool(_autoCheckUpdateKey) ?? true;
  }

  /// 设置自动检查更新
  Future<void> setAutoCheckUpdate(bool value) async {
    await _prefs?.setBool(_autoCheckUpdateKey, value);
  }

  /// 获取当前应用版本号
  Future<String> getCurrentVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  /// 自动检查更新（应用启动时调用）
  ///
  /// 如果设置中禁用了自动检查，则不执行
  /// 返回 [UpdateInfo] 如果有更新，否则返回 null
  Future<UpdateInfo?> autoCheckUpdate() async {
    if (!getAutoCheckUpdate()) return null;

    try {
      final updateInfo = await checkForUpdate();
      return updateInfo.hasUpdate ? updateInfo : null;
    } catch (e) {
      // 自动检查失败时静默处理
      return null;
    }
  }

  /// 检查更新（手动调用）
  ///
  /// 返回 [UpdateInfo] 如果检查成功
  /// 抛出异常如果检查失败
  Future<UpdateInfo> checkForUpdate() async {
    final currentVersion = await getCurrentVersion();

    final response = await _dio.get(
      _apiUrl,
      options: Options(responseType: ResponseType.json),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to check for updates: ${response.statusCode}');
    }

    final data = response.data as Map<String, dynamic>;
    final remoteVersion = (data['tag_name'] as String).replaceAll('v', '');
    final releaseUrl = data['html_url'] as String;
    var releaseNotes = data['body'] as String? ?? '';
    
    // 移除 release_template.md 的内容
    // 模板通常以 <div align=center> 开始用于显示下载徽章
    const templateMarker = '<div align=center>';
    final markerIndex = releaseNotes.indexOf(templateMarker);
    if (markerIndex != -1) {
      releaseNotes = releaseNotes.substring(0, markerIndex).trim();
    }

    final hasUpdate = _compareVersions(remoteVersion, currentVersion) > 0;

    return UpdateInfo(
      currentVersion: currentVersion,
      remoteVersion: remoteVersion,
      releaseUrl: releaseUrl,
      releaseNotes: releaseNotes,
      hasUpdate: hasUpdate,
    );
  }

  /// 比较两个版本号
  ///
  /// 返回值:
  /// - 正数: v1 > v2
  /// - 0: v1 == v2
  /// - 负数: v1 < v2
  int _compareVersions(String v1, String v2) {
    final parts1 = v1.split('.').map(int.parse).toList();
    final parts2 = v2.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 != p2) return p1.compareTo(p2);
    }
    return 0;
  }
}
