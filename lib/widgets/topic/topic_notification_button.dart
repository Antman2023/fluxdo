import 'package:flutter/material.dart';
import '../../models/topic.dart';

enum TopicNotificationButtonStyle {
  icon,
  chip,
}

/// 显示订阅级别选择面板
void showNotificationLevelSheet(
  BuildContext context,
  TopicNotificationLevel currentLevel,
  ValueChanged<TopicNotificationLevel> onSelected,
) {
  showModalBottomSheet(
    context: context,
    builder: (context) => _NotificationLevelSheet(
      currentLevel: currentLevel,
      onSelected: (newLevel) {
        Navigator.pop(context);
        onSelected(newLevel);
      },
    ),
  );
}

class TopicNotificationButton extends StatelessWidget {
  final TopicNotificationLevel level;
  final ValueChanged<TopicNotificationLevel>? onChanged;
  final TopicNotificationButtonStyle style;

  const TopicNotificationButton({
    super.key,
    required this.level,
    this.onChanged,
    this.style = TopicNotificationButtonStyle.icon,
  });

  static IconData getIcon(TopicNotificationLevel level) {
    switch (level) {
      case TopicNotificationLevel.muted:
        return Icons.notifications_off_outlined;
      case TopicNotificationLevel.regular:
        return Icons.notifications_none_outlined;
      case TopicNotificationLevel.tracking:
        return Icons.notifications_outlined;
      case TopicNotificationLevel.watching:
        return Icons.notifications_active;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (style == TopicNotificationButtonStyle.chip) {
      return _buildChip(context);
    }
    return _buildIconButton(context);
  }

  Widget _buildChip(BuildContext context) {
    final theme = Theme.of(context);
    final isWatching = level == TopicNotificationLevel.watching || 
                       level == TopicNotificationLevel.tracking;
    
    // 适配 AI 摘要按钮风格
    final bgColor = isWatching 
        ? theme.colorScheme.primaryContainer 
        : theme.colorScheme.primaryContainer.withValues(alpha:0.3);
    
    final fgColor = isWatching 
        ? theme.colorScheme.primary 
        : theme.colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onChanged != null ? () => _showSheet(context) : null,
        borderRadius: BorderRadius.circular(8), // 统一圆角为 8
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // 统一 Padding
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: isWatching 
              ? Border.all(color: theme.colorScheme.primary, width: 1)
              : null, // 非激活状态无边框，与 AI 摘要按钮保持一致
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                getIcon(level),
                size: 16,
                color: fgColor,
              ),
              const SizedBox(width: 6),
              Text(
                level.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: fgColor,
                  fontWeight: FontWeight.w500, // 统一字重
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton(BuildContext context) {
    return IconButton(
      onPressed: onChanged != null ? () => _showSheet(context) : null,
      icon: Icon(getIcon(level)),
      tooltip: level.label,
    );
  }

  void _showSheet(BuildContext context) {
    if (onChanged == null) return;
    showNotificationLevelSheet(context, level, onChanged!);
  }
}

class _NotificationLevelSheet extends StatelessWidget {
  final TopicNotificationLevel currentLevel;
  final ValueChanged<TopicNotificationLevel> onSelected;

  const _NotificationLevelSheet({
    required this.currentLevel,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              '订阅设置',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...TopicNotificationLevel.values.map((level) {
            final isSelected = level == currentLevel;
            return ListTile(
              leading: Icon(
                TopicNotificationButton.getIcon(level),
                color: isSelected ? theme.colorScheme.primary : null,
              ),
              title: Text(
                level.label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? theme.colorScheme.primary : null,
                ),
              ),
              subtitle: Text(
                level.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: isSelected
                  ? Icon(Icons.check, color: theme.colorScheme.primary)
                  : null,
              onTap: () => onSelected(level),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
