import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'update_service.dart';
import '../widgets/update_dialog.dart';

/// 更新检查助手类
///
/// 负责处理自动更新检查的 UI 逻辑
class UpdateCheckerHelper {
  /// 在应用启动时自动检查更新
  ///
  /// 如果发现新版本，会显示更新对话框
  static Future<void> checkUpdateOnStartup(
    BuildContext context,
    UpdateService updateService,
  ) async {
    final updateInfo = await updateService.autoCheckUpdate();
    if (updateInfo != null && context.mounted) {
      _showAutoUpdateDialog(context, updateInfo, updateService);
    }
  }

  /// 显示自动更新对话框
  static void _showAutoUpdateDialog(
    BuildContext context,
    UpdateInfo updateInfo,
    UpdateService updateService,
  ) {
    showDialog(
      context: context,
      builder: (context) => UpdateDialog(
        updateInfo: updateInfo,
        onUpdate: () {
          Navigator.of(context).pop();
          launchUrl(
            Uri.parse(updateInfo.releaseUrl),
            mode: LaunchMode.externalApplication,
          );
        },
        onCancel: () => Navigator.of(context).pop(),
        onIgnore: () {
          updateService.setAutoCheckUpdate(false);
          Navigator.of(context).pop();
        },
      ),
    );
  }
}
