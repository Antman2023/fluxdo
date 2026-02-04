import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/topic.dart';
import '../../pages/topic_detail_page/topic_detail_page.dart';
import '../../utils/time_utils.dart';
import '../common/smart_avatar.dart';
import '../content/discourse_html_content/discourse_html_content.dart';

/// 版主操作帖子组件（moderator_action）
/// 用于显示版主/管理员发布的操作性帖子（如移动帖子的通知等）
class ModeratorActionItem extends ConsumerWidget {
  final Post post;
  final int topicId;
  final VoidCallback? onReply;

  const ModeratorActionItem({
    super.key,
    required this.post,
    required this.topicId,
    this.onReply,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final avatarUrl = post.getAvatarUrl();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.15),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.5,
          ),
          left: BorderSide(
            color: theme.colorScheme.secondary,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: 版主标识 + Avatar + Name + Time
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 版主盾牌标识
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: theme.colorScheme.secondary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 12,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '版主操作',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Avatar
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.secondary.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: SmartAvatar(
                  imageUrl: avatarUrl.isNotEmpty ? avatarUrl : null,
                  radius: 16,
                  fallbackText: post.username,
                  backgroundColor: theme.colorScheme.secondaryContainer,
                ),
              ),
              const SizedBox(width: 8),
              // Name
              Expanded(
                child: Text(
                  (post.name != null && post.name!.isNotEmpty) ? post.name! : post.username,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: theme.colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              // Time + Post number
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    TimeUtils.formatRelativeTime(post.createdAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '#${post.postNumber}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Content (HTML)
          DiscourseHtmlContent(
            html: post.cooked,
            textStyle: theme.textTheme.bodyMedium?.copyWith(
              height: 1.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            linkCounts: post.linkCounts,
            onInternalLinkTap: (topicId, topicSlug) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TopicDetailPage(
                    topicId: topicId,
                    initialTitle: topicSlug,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
