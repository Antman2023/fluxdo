import 'package:flutter/material.dart';

/// 话题详情页底部操作栏
class TopicBottomBar extends StatelessWidget {
  final VoidCallback? onScrollToTop;
  final VoidCallback? onShare;
  final VoidCallback? onOpenInBrowser;
  final bool hasSummary;
  final bool isSummaryMode;
  final bool isLoading;
  final VoidCallback? onShowTopReplies;
  final VoidCallback? onCancelFilter;

  const TopicBottomBar({
    super.key,
    this.onScrollToTop,
    this.onShare,
    this.onOpenInBrowser,
    this.hasSummary = false,
    this.isSummaryMode = false,
    this.isLoading = false,
    this.onShowTopReplies,
    this.onCancelFilter,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      height: 80,
      padding: EdgeInsets.only(bottom: bottomPadding),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          // 回到顶部
          IconButton(
            onPressed: onScrollToTop,
            icon: const Icon(Icons.vertical_align_top),
            tooltip: '回到顶部',
          ),
          // 热门回复切换
          if (hasSummary)
            _buildTopRepliesButton(context),
          // 分享
          IconButton(
            onPressed: onShare,
            icon: const Icon(Icons.share_outlined),
            tooltip: '分享',
          ),
          // 在浏览器打开
          IconButton(
            onPressed: onOpenInBrowser,
            icon: const Icon(Icons.language),
            tooltip: '在浏览器打开',
          ),
        ],
      ),
    );
  }

  Widget _buildTopRepliesButton(BuildContext context) {
    final theme = Theme.of(context);

    return IconButton(
      onPressed: isLoading ? null : (isSummaryMode ? onCancelFilter : onShowTopReplies),
      icon: isLoading
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            )
          : Icon(
              isSummaryMode
                  ? Icons.local_fire_department
                  : Icons.local_fire_department_outlined,
              color: isSummaryMode ? theme.colorScheme.primary : null,
            ),
      style: IconButton.styleFrom(
        backgroundColor: isSummaryMode ? theme.colorScheme.primaryContainer : null,
      ),
      tooltip: isSummaryMode ? '查看全部' : '只看热门',
    );
  }
}
