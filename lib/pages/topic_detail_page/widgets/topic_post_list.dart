import 'package:flutter/material.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import '../../../models/topic.dart';
import '../../../providers/message_bus_providers.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/post/post_item/post_item.dart';
import '../../../widgets/post/post_item_skeleton.dart';
import 'topic_detail_header.dart';
import 'typing_indicator.dart';

/// 话题帖子列表
/// 负责构建 CustomScrollView 及其 Slivers
///
/// 每个帖子独立生成一个 SliverToBoxAdapter，实现帖子级虚拟化：
/// Flutter 只构建视口附近的帖子，远离视口的帖子不会被构建。
/// 长帖子内部的 HTML 分块由 ChunkedHtmlContent 的 Column + SelectionArea 处理，
/// 保留跨块文本选择能力。
class TopicPostList extends StatelessWidget {
  final TopicDetail detail;
  final AutoScrollController scrollController;
  final GlobalKey centerKey;
  final GlobalKey headerKey;
  final int? highlightPostNumber;
  final List<TypingUser> typingUsers;
  final bool isLoggedIn;
  final bool hasMoreBefore;
  final bool hasMoreAfter;
  final bool isLoadingPrevious;
  final bool isLoadingMore;
  final int centerPostIndex;
  final int? dividerPostIndex;
  final void Function(int postNumber, bool isVisible) onPostVisibilityChanged;
  final void Function(int postNumber) onJumpToPost;
  final void Function(Post? replyToPost) onReply;
  final void Function(Post post) onEdit;
  final void Function(Post post)? onShareAsImage;
  final void Function(int postId) onRefreshPost;
  final void Function(int, bool) onVoteChanged;
  final void Function(TopicNotificationLevel)? onNotificationLevelChanged;
  final void Function(int postId, bool accepted)? onSolutionChanged;
  final bool Function(ScrollNotification) onScrollNotification;

  const TopicPostList({
    super.key,
    required this.detail,
    required this.scrollController,
    required this.centerKey,
    required this.headerKey,
    required this.highlightPostNumber,
    required this.typingUsers,
    required this.isLoggedIn,
    required this.hasMoreBefore,
    required this.hasMoreAfter,
    required this.isLoadingPrevious,
    required this.isLoadingMore,
    required this.centerPostIndex,
    required this.dividerPostIndex,
    required this.onPostVisibilityChanged,
    required this.onJumpToPost,
    required this.onReply,
    required this.onEdit,
    this.onShareAsImage,
    required this.onRefreshPost,
    required this.onVoteChanged,
    this.onNotificationLevelChanged,
    this.onSolutionChanged,
    required this.onScrollNotification,
  });

  /// 在大屏上为内容添加宽度约束
  Widget _wrapContent(BuildContext context, Widget child) {
    if (Responsive.isMobile(context)) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Breakpoints.maxContentWidth),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final posts = detail.postStream.posts;
    final hasFirstPost = posts.isNotEmpty && posts.first.postNumber == 1;

    final loadMoreSkeletonCount = calculateSkeletonCount(
      MediaQuery.of(context).size.height * 0.4,
      minCount: 2,
    );

    return NotificationListener<ScrollNotification>(
      onNotification: onScrollNotification,
      child: CustomScrollView(
        controller: scrollController,
        center: centerKey,
        cacheExtent: 500,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          // 向上加载骨架屏
          if (hasMoreBefore && isLoadingPrevious)
            LoadingSkeletonSliver(
              itemCount: loadMoreSkeletonCount,
              wrapContent: _wrapContent,
            ),

          // 话题 Header（centerPostIndex > 0 时放在 before-center 区域）
          if (hasFirstPost && centerPostIndex > 0)
            SliverToBoxAdapter(
              child: _wrapContent(
                context,
                TopicDetailHeader(
                  detail: detail,
                  headerKey: headerKey,
                  onVoteChanged: onVoteChanged,
                  onNotificationLevelChanged: onNotificationLevelChanged,
                ),
              ),
            ),

          // Before-center 帖子（文档顺序，Viewport 自动反转渲染）
          for (int i = 0; i < centerPostIndex; i++)
            _buildPostSliver(context, theme, posts[i], i),

          // 中心帖子（带 centerKey）
          _buildCenterSliver(context, theme, posts, hasFirstPost),

          // After-center 帖子
          for (int i = centerPostIndex + 1; i < posts.length; i++)
            _buildPostSliver(context, theme, posts[i], i),

          // 正在输入指示器（始终占位，通过 AnimatedSize 平滑过渡避免列表抖动）
          if (!hasMoreAfter)
            SliverToBoxAdapter(
              child: _wrapContent(
                context,
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.topCenter,
                  child: TypingAvatars(users: typingUsers),
                ),
              ),
            ),

          // 底部加载骨架屏
          if (hasMoreAfter && isLoadingMore)
            LoadingSkeletonSliver(
              itemCount: loadMoreSkeletonCount,
              wrapContent: _wrapContent,
            ),
          SliverPadding(
            padding: EdgeInsets.only(bottom: 80 + MediaQuery.of(context).padding.bottom),
          ),
        ],
      ),
    );
  }

  /// 构建中心帖子 Sliver
  Widget _buildCenterSliver(BuildContext context, ThemeData theme, List<Post> posts, bool hasFirstPost) {
    if (centerPostIndex == 0 && hasFirstPost) {
      // 话题 Header 和第一个帖子组合为 center
      return SliverMainAxisGroup(
        key: centerKey,
        slivers: [
          SliverToBoxAdapter(
            child: _wrapContent(
              context,
              TopicDetailHeader(
                detail: detail,
                headerKey: headerKey,
                onVoteChanged: onVoteChanged,
                onNotificationLevelChanged: onNotificationLevelChanged,
              ),
            ),
          ),
          _buildPostSliver(context, theme, posts[0], 0),
        ],
      );
    }
    return _buildPostSliver(
      context, theme, posts[centerPostIndex], centerPostIndex,
      key: centerKey,
    );
  }

  /// 构建单个帖子 Sliver
  ///
  /// 每个帖子独立一个 SliverToBoxAdapter，实现帖子级虚拟化。
  /// 长帖子的 HTML 分块由 PostItem 内的 ChunkedHtmlContent 处理（Column + SelectionArea），
  /// 保留跨块文本选择。
  Widget _buildPostSliver(BuildContext context, ThemeData theme, Post post, int postIndex, {Key? key}) {
    final showDivider = dividerPostIndex == postIndex;

    return SliverToBoxAdapter(
      key: key,
      child: _wrapContent(
        context,
        AutoScrollTag(
          key: ValueKey('post-${post.postNumber}'),
          controller: scrollController,
          index: postIndex,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showDivider)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                  child: Text(
                    '上次看到这里',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              PostItem(
                post: post,
                topicId: detail.id,
                highlight: highlightPostNumber == post.postNumber,
                isTopicOwner: detail.createdBy?.username == post.username,
                topicHasAcceptedAnswer: detail.hasAcceptedAnswer,
                acceptedAnswerPostNumber: detail.acceptedAnswerPostNumber,
                onLike: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('点赞功能开发中...')),
                ),
                onReply: isLoggedIn ? () => onReply(post.postNumber == 1 ? null : post) : null,
                onEdit: isLoggedIn && post.canEdit ? () => onEdit(post) : null,
                onShareAsImage: onShareAsImage != null ? () => onShareAsImage!(post) : null,
                onRefreshPost: onRefreshPost,
                onJumpToPost: onJumpToPost,
                onSolutionChanged: onSolutionChanged,
                onVisibilityChanged: (isVisible) =>
                    onPostVisibilityChanged(post.postNumber, isVisible),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
