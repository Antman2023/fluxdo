import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/topic.dart';
import '../../providers/discourse_providers.dart';
import '../../utils/time_utils.dart';

/// 话题 AI 摘要组件
class TopicSummaryWidget extends ConsumerWidget {
  final int topicId;

  const TopicSummaryWidget({
    super.key,
    required this.topicId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(topicSummaryProvider(topicId));
    final theme = Theme.of(context);

    // 使用 AnimatedSize 和 AnimatedSwitcher 优化状态切换动画
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            alignment: Alignment.topCenter,
            children: <Widget>[
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        child: summaryAsync.when(
          loading: () => KeyedSubtree(
            key: const ValueKey('loading'),
            child: _buildLoadingState(theme),
          ),
          error: (error, stack) => KeyedSubtree(
            key: const ValueKey('error'),
            child: _buildErrorState(theme, error, ref),
          ),
          data: (summary) {
            if (summary == null) {
              return KeyedSubtree(
                key: const ValueKey('empty'),
                child: _buildEmptyState(theme),
              );
            }
            return KeyedSubtree(
              key: const ValueKey('data'),
              child: _buildSummaryContent(context, theme, summary, ref),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoadingState(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '正在生成摘要...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme, Object error, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha:0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 20,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '加载摘要失败',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          TextButton(
            onPressed: () => ref.invalidate(topicSummaryProvider(topicId)),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Text(
            '暂无摘要',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryContent(
    BuildContext context,
    ThemeData theme,
    TopicSummary summary,
    WidgetRef ref,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha:0.5),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'AI 摘要',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              // 过期提示
              if (summary.outdated)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '有 ${summary.newPostsSinceSummary} 条新回复',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // 摘要内容
          SelectableText(
            summary.summarizedText,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.6,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          // 底部信息
          Row(
            children: [
              if (summary.updatedAt != null)
                Text(
                  '更新于 ${TimeUtils.formatRelativeTime(summary.updatedAt!)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const Spacer(),
              // 刷新按钮
              if (summary.canRegenerate && summary.outdated)
                TextButton.icon(
                  onPressed: () => _refreshSummary(ref),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('刷新'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _refreshSummary(WidgetRef ref) {
    ref.invalidate(topicSummaryProvider(topicId));
  }
}

/// 可折叠的话题摘要组件（懒加载：点击时才请求）
class CollapsibleTopicSummary extends ConsumerStatefulWidget {
  final int topicId;
  final TopicDetail? topicDetail;  // 新增：传入话题详情以检查 summarizable
  final Widget? headerExtra; // 新增：头部额外组件（如订阅按钮）

  const CollapsibleTopicSummary({
    super.key,
    required this.topicId,
    this.topicDetail,
    this.headerExtra,
  });

  @override
  ConsumerState<CollapsibleTopicSummary> createState() =>
      _CollapsibleTopicSummaryState();
}

class _CollapsibleTopicSummaryState
    extends ConsumerState<CollapsibleTopicSummary>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  bool _hasRequested = false; // 是否已触发过请求
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topicDetail = widget.topicDetail;

    // 🔑 关键控制逻辑：检查是否应该显示摘要按钮
    if (topicDetail != null && !topicDetail.summarizable) {
      // 即使不可摘要，如果有 headerExtra 也要显示 headerExtra
      if (widget.headerExtra != null) {
         return widget.headerExtra!;
      }
      return const SizedBox.shrink();
    }

    // 只有在已请求后才 watch provider
    final summaryAsync = _hasRequested
        ? ref.watch(topicSummaryProvider(widget.topicId))
        : null;

    final isLoading = summaryAsync?.isLoading == true;
    final isOutdated = summaryAsync?.value?.outdated == true;
    final hasCachedSummary = topicDetail?.hasCachedSummary ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // 摘要按钮
            InkWell(
              onTap: _toggleExpand,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha:0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasCachedSummary ? 'AI 摘要' : '生成 AI 摘要',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // 旋转动画箭头
                    AnimatedRotation(
                      turns: _isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.expand_more,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    // 加载指示器
                    if (isLoading) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                    // 过期提示
                    if (isOutdated) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.tertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (widget.headerExtra != null) ...[
              const SizedBox(width: 12),
              widget.headerExtra!,
            ],
          ],
        ),
        // 展开的摘要内容，使用 SizeTransition 优化展开动画
        SizeTransition(
          sizeFactor: _animation,
          axisAlignment: -1.0, // 从顶部展开
          child: _hasRequested
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TopicSummaryWidget(topicId: widget.topicId),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
        // 首次展开时标记已请求，触发 provider
        if (!_hasRequested) {
          _hasRequested = true;
        }
      } else {
        _controller.reverse();
      }
    });
  }
}
