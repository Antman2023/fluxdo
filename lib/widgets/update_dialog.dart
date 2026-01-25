import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';

class UpdateDialog extends StatelessWidget {
  final UpdateInfo updateInfo;
  final VoidCallback onUpdate;
  final VoidCallback onCancel;
  final VoidCallback? onIgnore;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
    required this.onUpdate,
    required this.onCancel,
    this.onIgnore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Image/Icon
            Container(
              height: 140,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: -20,
                    right: -20,
                    child: Icon(
                      Icons.rocket_launch_rounded,
                      size: 120,
                      color: colorScheme.primary.withOpacity(0.1),
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.primary.withOpacity(0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.rocket_launch_rounded,
                          size: 40,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '发现新版本',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   // Version Comparison
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildVersionChip(context, updateInfo.currentVersion, false),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(Icons.arrow_forward_rounded, 
                          size: 20, 
                          color: colorScheme.outline,
                        ),
                      ),
                      _buildVersionChip(context, updateInfo.remoteVersion, true),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Release Notes
                  if (updateInfo.releaseNotes.isNotEmpty) ...[
                    Text(
                      '更新内容',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withOpacity(0.5),
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: HtmlWidget(
                          md.markdownToHtml(updateInfo.releaseNotes),
                          textStyle: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                          customStylesBuilder: (element) {
                            if (element.localName == 'ul' || element.localName == 'ol') {
                              return {'padding-left': '20px'};
                            }
                            return null;
                          },
                          onTapUrl: (url) async {
                             return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Actions
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: onUpdate,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('立即更新'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (onIgnore != null)
                        Expanded(
                          child: TextButton(
                            onPressed: onIgnore,
                            style: TextButton.styleFrom(
                              foregroundColor: colorScheme.onSurfaceVariant,
                            ),
                            child: const Text('不再提醒'),
                          ),
                        ),
                      Expanded(
                        child: TextButton(
                          onPressed: onCancel,
                          style: TextButton.styleFrom(
                            foregroundColor: colorScheme.onSurfaceVariant,
                          ),
                          child: const Text('稍后'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionChip(BuildContext context, String version, bool isNew) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isNew ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: isNew ? Border.all(color: colorScheme.primary.withOpacity(0.5)) : null,
      ),
      child: Text(
        'v$version',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: isNew ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
