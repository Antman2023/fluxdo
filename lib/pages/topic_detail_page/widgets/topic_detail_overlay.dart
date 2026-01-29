import 'package:flutter/material.dart';
import '../../../models/topic.dart';
import '../../../widgets/topic/topic_progress.dart';
import 'topic_bottom_bar.dart';

/// 话题详情页浮层
/// 包含进度栏、底部操作栏和悬浮回复按钮
class TopicDetailOverlay extends StatelessWidget {
  final bool showBottomBar;
  final bool isLoggedIn;
  final int currentStreamIndex;
  final int totalCount;
  final TopicDetail detail;
  final VoidCallback onScrollToTop;
  final VoidCallback onShare;
  final VoidCallback onOpenInBrowser;
  final VoidCallback onReply;
  final VoidCallback onProgressTap;
  final bool isSummaryMode;
  final bool isLoading;
  final VoidCallback? onShowTopReplies;
  final VoidCallback? onCancelFilter;

  const TopicDetailOverlay({
    super.key,
    required this.showBottomBar,
    required this.isLoggedIn,
    required this.currentStreamIndex,
    required this.totalCount,
    required this.detail,
    required this.onScrollToTop,
    required this.onShare,
    required this.onOpenInBrowser,
    required this.onReply,
    required this.onProgressTap,
    this.isSummaryMode = false,
    this.isLoading = false,
    this.onShowTopReplies,
    this.onCancelFilter,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final progressPercent = totalCount > 1
        ? (currentStreamIndex - 1) / (totalCount - 1)
        : 0.0;

    return Stack(
      children: [
        // 固定的进度栏
        AnimatedPositioned(
          key: const ValueKey('progress_bar'),
          duration: const Duration(milliseconds: 200),
          bottom: showBottomBar ? 96 : 24 + bottomPadding,
          left: 0,
          right: 0,
          child: Center(
            child: TopicProgress(
              currentIndex: currentStreamIndex,
              totalCount: totalCount,
              progressPercent: progressPercent,
              onTap: onProgressTap,
            ),
          ),
        ),
        // 底部操作栏
        AnimatedPositioned(
          key: const ValueKey('bottom_bar'),
          duration: const Duration(milliseconds: 200),
          left: 0,
          right: 0,
          bottom: showBottomBar ? 0 : -80,
          child: TopicBottomBar(
            onScrollToTop: onScrollToTop,
            onShare: onShare,
            onOpenInBrowser: onOpenInBrowser,
            hasSummary: detail.hasSummary,
            isSummaryMode: isSummaryMode,
            isLoading: isLoading,
            onShowTopReplies: onShowTopReplies,
            onCancelFilter: onCancelFilter,
          ),
        ),
        // 悬浮回复按钮
        if (isLoggedIn)
          AnimatedPositioned(
            key: const ValueKey('fab_reply'),
            duration: const Duration(milliseconds: 200),
            right: 16,
            bottom: showBottomBar
                ? bottomPadding + (80 - bottomPadding - 56) / 2
                : 16 + bottomPadding,
            child: FloatingActionButton(
              onPressed: onReply,
              child: const Icon(Icons.reply),
            ),
          ),
      ],
    );
  }
}
