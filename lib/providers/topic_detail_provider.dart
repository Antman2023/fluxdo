import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/topic.dart';
import 'core_providers.dart';

/// 话题详情参数
/// 使用 instanceId 确保每次打开页面都是独立的 provider 实例
/// 解决：打开话题 -> 点击用户 -> 再进入同一话题时应该是新的页面状态
class TopicDetailParams {
  final int topicId;
  final int? postNumber;
  /// 唯一实例 ID，确保每次打开页面都创建新的 provider 实例
  /// 默认为空字符串，用于 MessageBus 等不需要精确匹配的场景
  final String instanceId;

  const TopicDetailParams(this.topicId, {this.postNumber, this.instanceId = ''});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TopicDetailParams &&
          topicId == other.topicId &&
          instanceId == other.instanceId;

  @override
  int get hashCode => Object.hash(topicId, instanceId);
}

/// 话题详情 Notifier (支持双向加载)
class TopicDetailNotifier extends AsyncNotifier<TopicDetail> {
  TopicDetailNotifier(this.arg);
  final TopicDetailParams arg;

  bool _hasMoreAfter = true;
  bool _hasMoreBefore = true;
  bool _isLoadingPrevious = false;
  bool _isLoadingMore = false;
  bool get hasMoreAfter => _hasMoreAfter;
  bool get hasMoreBefore => _hasMoreBefore;
  bool get isLoadingPrevious => _isLoadingPrevious;
  bool get isLoadingMore => _isLoadingMore;

  @override
  Future<TopicDetail> build() async {
    print('[TopicDetailNotifier] build called with topicId=${arg.topicId}, postNumber=${arg.postNumber}');
    _hasMoreAfter = true;
    _hasMoreBefore = true;
    final service = ref.read(discourseServiceProvider);
    // 初始加载时传 trackVisit: true，记录用户访问
    final detail = await service.getTopicDetail(arg.topicId, postNumber: arg.postNumber, trackVisit: true);

    final posts = detail.postStream.posts;
    final stream = detail.postStream.stream;
    if (posts.isEmpty) {
      _hasMoreAfter = false;
      _hasMoreBefore = false;
    } else {
      final firstPostId = posts.first.id;
      final firstIndex = stream.indexOf(firstPostId);
      _hasMoreBefore = firstIndex > 0;

      final lastPostId = posts.last.id;
      final lastIndex = stream.indexOf(lastPostId);
      _hasMoreAfter = lastIndex < stream.length - 1;
    }

    return detail;
  }

  /// 加载更早的帖子（向上滚动）
  Future<void> loadPrevious() async {
    if (!_hasMoreBefore || state.isLoading || _isLoadingPrevious) return;
    _isLoadingPrevious = true;

    try {
      state = const AsyncLoading<TopicDetail>().copyWithPrevious(state);

      state = await AsyncValue.guard(() async {
        final currentDetail = state.requireValue;
        final currentPosts = currentDetail.postStream.posts;

        if (currentPosts.isEmpty) {
          _hasMoreBefore = false;
          return currentDetail;
        }

        final firstPostNumber = currentPosts.first.postNumber;
        if (firstPostNumber <= 1) {
          _hasMoreBefore = false;
          return currentDetail;
        }

        final service = ref.read(discourseServiceProvider);
        // 使用 posts.json 接口，向上加载（asc: false）
        final newPostStream = await service.getPostsByNumber(
          arg.topicId,
          postNumber: firstPostNumber,
          asc: false,
        );

        // 合并帖子：新加载的 + 当前的（去重）
        final existingIds = currentPosts.map((p) => p.id).toSet();
        final newPosts = newPostStream.posts.where((p) => !existingIds.contains(p.id)).toList();
        final mergedPosts = [...newPosts, ...currentPosts];
        mergedPosts.sort((a, b) => a.postNumber.compareTo(b.postNumber));

        // 合并 stream：将新帖子的 ID 添加到 stream 中（向前插入）
        final currentStream = currentDetail.postStream.stream;
        final existingStreamIds = currentStream.toSet();
        final newPostIds = newPosts.map((p) => p.id).where((id) => !existingStreamIds.contains(id)).toList();
        final mergedStream = [...newPostIds, ...currentStream];

        _hasMoreBefore = mergedPosts.first.postNumber > 1;

        return TopicDetail(
          id: currentDetail.id,
          title: currentDetail.title,
          slug: currentDetail.slug,
          postsCount: currentDetail.postsCount,
          postStream: PostStream(posts: mergedPosts, stream: mergedStream),
          categoryId: currentDetail.categoryId,
          closed: currentDetail.closed,
          archived: currentDetail.archived,
          tags: currentDetail.tags,
          views: currentDetail.views,
          likeCount: currentDetail.likeCount,
          createdAt: currentDetail.createdAt,
          visible: currentDetail.visible,
          canVote: currentDetail.canVote,
          voteCount: currentDetail.voteCount,
          userVoted: currentDetail.userVoted,
        );
      });
    } finally {
      _isLoadingPrevious = false;
    }
  }

  /// 加载更多回复（向下滚动）
  Future<void> loadMore() async {
    if (!_hasMoreAfter || state.isLoading || _isLoadingMore) return;
    _isLoadingMore = true;

    try {
      state = const AsyncLoading<TopicDetail>().copyWithPrevious(state);

      state = await AsyncValue.guard(() async {
        final currentDetail = state.requireValue;
        final currentPosts = currentDetail.postStream.posts;

        if (currentPosts.isEmpty) {
          _hasMoreAfter = false;
          return currentDetail;
        }

        final lastPostNumber = currentPosts.last.postNumber;
        if (lastPostNumber >= currentDetail.postsCount) {
          _hasMoreAfter = false;
          return currentDetail;
        }

        final service = ref.read(discourseServiceProvider);
        // 使用 posts.json 接口，向下加载（asc: true）
        final newPostStream = await service.getPostsByNumber(
          arg.topicId,
          postNumber: lastPostNumber,
          asc: true,
        );

        // 合并帖子：当前的 + 新加载的（去重）
        final existingIds = currentPosts.map((p) => p.id).toSet();
        final newPosts = newPostStream.posts.where((p) => !existingIds.contains(p.id)).toList();
        final mergedPosts = [...currentPosts, ...newPosts];
        mergedPosts.sort((a, b) => a.postNumber.compareTo(b.postNumber));

        // 合并 stream：将新帖子的 ID 添加到 stream 中（向后追加）
        final currentStream = currentDetail.postStream.stream;
        final existingStreamIds = currentStream.toSet();
        final newPostIds = newPosts.map((p) => p.id).where((id) => !existingStreamIds.contains(id)).toList();
        final mergedStream = [...currentStream, ...newPostIds];

        _hasMoreAfter = mergedPosts.last.postNumber < currentDetail.postsCount;

        return TopicDetail(
          id: currentDetail.id,
          title: currentDetail.title,
          slug: currentDetail.slug,
          postsCount: currentDetail.postsCount,
          postStream: PostStream(posts: mergedPosts, stream: mergedStream),
          categoryId: currentDetail.categoryId,
          closed: currentDetail.closed,
          archived: currentDetail.archived,
          tags: currentDetail.tags,
          views: currentDetail.views,
          likeCount: currentDetail.likeCount,
          createdAt: currentDetail.createdAt,
          visible: currentDetail.visible,
          canVote: currentDetail.canVote,
          voteCount: currentDetail.voteCount,
          userVoted: currentDetail.userVoted,
        );
      });
    } finally {
      _isLoadingMore = false;
    }
  }

  /// 加载新回复（用于 MessageBus 实时更新）
  /// 只有当已加载到最后一页时才会执行
  Future<void> loadNewReplies() async {
    // 只检查是否正在加载，移除 _hasMoreAfter 检查
    if (state.isLoading) return;

    final currentDetail = state.value;
    if (currentDetail == null) return;

    final currentPosts = currentDetail.postStream.posts;
    if (currentPosts.isEmpty) return;

    final lastPostNumber = currentPosts.last.postNumber;

    // 通过比较最后一个帖子号和总帖子数来判断是否在底部
    // 这样即使 _hasMoreAfter 被重置也不影响判断
    if (lastPostNumber < currentDetail.postsCount) {
      // 还有更多帖子未加载到，说明不在底部，不执行新回复加载
      return;
    }

    // 从最后一个帖子往后加载
    final targetPostNumber = lastPostNumber + 1;
    
    try {
      final service = ref.read(discourseServiceProvider);
      final newDetail = await service.getTopicDetail(arg.topicId, postNumber: targetPostNumber);
      
      // 如果没有新帖子
      if (newDetail.postStream.posts.isEmpty) return;
      
      // 合并帖子
      final existingIds = currentPosts.map((p) => p.id).toSet();
      final newPosts = newDetail.postStream.posts.where((p) => !existingIds.contains(p.id)).toList();
      
      if (newPosts.isEmpty) return;
      
      final mergedPosts = [...currentPosts, ...newPosts];
      mergedPosts.sort((a, b) => a.postNumber.compareTo(b.postNumber));
      
      // 合并 stream：将新帖子的 ID 添加到 stream 中
      final currentStream = currentDetail.postStream.stream;
      final existingStreamIds = currentStream.toSet();
      final newPostIds = newPosts.map((p) => p.id).where((id) => !existingStreamIds.contains(id)).toList();
      final mergedStream = [...currentStream, ...newPostIds];
      
      _hasMoreAfter = mergedPosts.last.postNumber < newDetail.postsCount;
      
      state = AsyncValue.data(TopicDetail(
        id: currentDetail.id,
        title: currentDetail.title,
        slug: currentDetail.slug,
        postsCount: newDetail.postsCount, // 更新总数
        postStream: PostStream(posts: mergedPosts, stream: mergedStream), // 使用合并后的 stream
        categoryId: currentDetail.categoryId,
        closed: currentDetail.closed,
        archived: currentDetail.archived,
        tags: currentDetail.tags,
        views: currentDetail.views,
        likeCount: currentDetail.likeCount,
        createdAt: currentDetail.createdAt,
        visible: currentDetail.visible,
        canVote: newDetail.canVote,
        voteCount: newDetail.voteCount,
        userVoted: newDetail.userVoted,
      ));
    } catch (e) {
      print('[TopicDetail] 加载新回复失败: $e');
    }
  }

  /// 刷新单个帖子（用于 MessageBus revised/rebaked 消息）
  Future<void> refreshPost(int postId, {bool preserveCooked = false}) async {
    final currentDetail = state.value;
    if (currentDetail == null) return;

    final currentPosts = currentDetail.postStream.posts;
    final index = currentPosts.indexWhere((p) => p.id == postId);
    if (index == -1) return;

    try {
      final service = ref.read(discourseServiceProvider);
      final postNumber = currentPosts[index].postNumber;
      final newDetail = await service.getTopicDetail(arg.topicId, postNumber: postNumber);
      
      // 找到更新后的帖子
      final updatedPost = newDetail.postStream.posts.firstWhere(
        (p) => p.id == postId,
        orElse: () => currentPosts[index],
      );
      
      // 如果需要保留 cooked（如 acted 类型），则只更新其他字段
      final finalPost = preserveCooked 
          ? Post(
              id: updatedPost.id,
              name: updatedPost.name,
              username: updatedPost.username,
              avatarTemplate: updatedPost.avatarTemplate,
              cooked: currentPosts[index].cooked, // 保留原 cooked
              postNumber: updatedPost.postNumber,
              postType: updatedPost.postType,
              updatedAt: updatedPost.updatedAt,
              createdAt: updatedPost.createdAt,
              likeCount: updatedPost.likeCount,
              replyCount: updatedPost.replyCount,
              replyToPostNumber: updatedPost.replyToPostNumber,
              replyToUser: updatedPost.replyToUser,
              scoreHidden: updatedPost.scoreHidden,
              canEdit: updatedPost.canEdit,
              canDelete: updatedPost.canDelete,
              canRecover: updatedPost.canRecover,
              canWiki: updatedPost.canWiki,
              bookmarked: updatedPost.bookmarked,
              read: currentPosts[index].read, // 保留原 read 状态
              actionsSummary: updatedPost.actionsSummary,
              linkCounts: updatedPost.linkCounts,
              reactions: updatedPost.reactions,
              currentUserReaction: updatedPost.currentUserReaction,
            )
          : updatedPost;
      
      final newPosts = [...currentPosts];
      newPosts[index] = finalPost;
      
      state = AsyncValue.data(TopicDetail(
        id: currentDetail.id,
        title: currentDetail.title,
        slug: currentDetail.slug,
        postsCount: currentDetail.postsCount,
        postStream: PostStream(posts: newPosts, stream: currentDetail.postStream.stream),
        categoryId: currentDetail.categoryId,
        closed: currentDetail.closed,
        archived: currentDetail.archived,
        tags: currentDetail.tags,
        views: currentDetail.views,
        likeCount: currentDetail.likeCount,
        createdAt: currentDetail.createdAt,
        visible: currentDetail.visible,
      ));
    } catch (e) {
      print('[TopicDetail] 刷新帖子 $postId 失败: $e');
    }
  }

  /// 从列表中移除帖子（用于 MessageBus destroyed 消息）
  void removePost(int postId) {
    final currentDetail = state.value;
    if (currentDetail == null) return;

    final currentPosts = currentDetail.postStream.posts;
    final newPosts = currentPosts.where((p) => p.id != postId).toList();
    
    if (newPosts.length == currentPosts.length) return; // 没有变化
    
    state = AsyncValue.data(TopicDetail(
      id: currentDetail.id,
      title: currentDetail.title,
      slug: currentDetail.slug,
      postsCount: currentDetail.postsCount - 1,
      postStream: PostStream(posts: newPosts, stream: currentDetail.postStream.stream),
      categoryId: currentDetail.categoryId,
      closed: currentDetail.closed,
      archived: currentDetail.archived,
      tags: currentDetail.tags,
      views: currentDetail.views,
      likeCount: currentDetail.likeCount,
      createdAt: currentDetail.createdAt,
      visible: currentDetail.visible,
    ));
  }

  /// 标记帖子被删除（用于 MessageBus deleted 消息）
  /// 对于软删除，通常只是标记状态而不是移除
  void markPostDeleted(int postId) {
    // 对于软删除，我们可以刷新该帖子来获取最新状态
    refreshPost(postId);
  }

  /// 标记帖子已恢复（用于 MessageBus recovered 消息）
  void markPostRecovered(int postId) {
    // 刷新该帖子来获取最新状态
    refreshPost(postId);
  }

  /// 更新帖子点赞数（用于 MessageBus liked/unliked 消息）
  void updatePostLikes(int postId, {int? likesCount}) {
    if (likesCount == null) {
      // 如果没有提供点赞数，刷新整个帖子
      refreshPost(postId, preserveCooked: true);
      return;
    }
    
    final currentDetail = state.value;
    if (currentDetail == null) return;

    final currentPosts = currentDetail.postStream.posts;
    final index = currentPosts.indexWhere((p) => p.id == postId);
    if (index == -1) return;

    final oldPost = currentPosts[index];
    
    // 只更新 likeCount
    final updatedPost = Post(
      id: oldPost.id,
      name: oldPost.name,
      username: oldPost.username,
      avatarTemplate: oldPost.avatarTemplate,
      cooked: oldPost.cooked,
      postNumber: oldPost.postNumber,
      postType: oldPost.postType,
      updatedAt: oldPost.updatedAt,
      createdAt: oldPost.createdAt,
      likeCount: likesCount,
      replyCount: oldPost.replyCount,
      replyToPostNumber: oldPost.replyToPostNumber,
      replyToUser: oldPost.replyToUser,
      scoreHidden: oldPost.scoreHidden,
      canEdit: oldPost.canEdit,
      canDelete: oldPost.canDelete,
      canRecover: oldPost.canRecover,
      canWiki: oldPost.canWiki,
      bookmarked: oldPost.bookmarked,
      read: oldPost.read,
      actionsSummary: oldPost.actionsSummary,
      linkCounts: oldPost.linkCounts,
      reactions: oldPost.reactions,
      currentUserReaction: oldPost.currentUserReaction,
    );
    
    final newPosts = [...currentPosts];
    newPosts[index] = updatedPost;
    
    state = AsyncValue.data(TopicDetail(
      id: currentDetail.id,
      title: currentDetail.title,
      slug: currentDetail.slug,
      postsCount: currentDetail.postsCount,
      postStream: PostStream(posts: newPosts, stream: currentDetail.postStream.stream),
      categoryId: currentDetail.categoryId,
      closed: currentDetail.closed,
      archived: currentDetail.archived,
      tags: currentDetail.tags,
      views: currentDetail.views,
      likeCount: currentDetail.likeCount,
      createdAt: currentDetail.createdAt,
      visible: currentDetail.visible,
    ));
  }

  /// 更新单个帖子的点赞/回应状态
  void updatePostReaction(int postId, List<PostReaction> reactions, PostReaction? currentUserReaction) {
    final currentDetail = state.value;
    if (currentDetail == null) return;

    final currentPosts = currentDetail.postStream.posts;
    final index = currentPosts.indexWhere((p) => p.id == postId);
    if (index == -1) return;

    final oldPost = currentPosts[index];

    // 创建新的 Post 对象，只更新 reactions 和 currentUserReaction
    final updatedPost = Post(
      id: oldPost.id,
      name: oldPost.name,
      username: oldPost.username,
      avatarTemplate: oldPost.avatarTemplate,
      cooked: oldPost.cooked,
      postNumber: oldPost.postNumber,
      postType: oldPost.postType,
      updatedAt: oldPost.updatedAt,
      createdAt: oldPost.createdAt,
      likeCount: oldPost.likeCount,
      replyCount: oldPost.replyCount,
      replyToPostNumber: oldPost.replyToPostNumber,
      replyToUser: oldPost.replyToUser,
      scoreHidden: oldPost.scoreHidden,
      canEdit: oldPost.canEdit,
      canDelete: oldPost.canDelete,
      canRecover: oldPost.canRecover,
      canWiki: oldPost.canWiki,
      bookmarked: oldPost.bookmarked,
      read: oldPost.read,
      actionsSummary: oldPost.actionsSummary,
      linkCounts: oldPost.linkCounts,
      // 更新这两个字段
      reactions: reactions,
      currentUserReaction: currentUserReaction,
    );

    // 创建新的 posts 列表
    final newPosts = [...currentPosts];
    newPosts[index] = updatedPost;

    // 更新 state
    state = AsyncValue.data(TopicDetail(
      id: currentDetail.id,
      title: currentDetail.title,
      slug: currentDetail.slug,
      postsCount: currentDetail.postsCount,
      postStream: PostStream(
        posts: newPosts,
        stream: currentDetail.postStream.stream,
      ),
      categoryId: currentDetail.categoryId,
      closed: currentDetail.closed,
      archived: currentDetail.archived,
      tags: currentDetail.tags,
      views: currentDetail.views,
      likeCount: currentDetail.likeCount,
      createdAt: currentDetail.createdAt,
      visible: currentDetail.visible,
    ));
  }

  /// 使用新的起始帖子号重新加载数据
  /// 用于跳转到不在当前列表中的帖子
  Future<void> reloadWithPostNumber(int postNumber) async {
    state = const AsyncValue.loading();
    _hasMoreAfter = true;
    _hasMoreBefore = true;

    // 等待一帧，确保 loading 状态被渲染
    await Future.delayed(Duration.zero);

    state = await AsyncValue.guard(() async {
      final service = ref.read(discourseServiceProvider);
      final detail = await service.getTopicDetail(arg.topicId, postNumber: postNumber);

      final posts = detail.postStream.posts;
      final stream = detail.postStream.stream;
      if (posts.isEmpty) {
        _hasMoreAfter = false;
        _hasMoreBefore = false;
      } else {
        final firstPostId = posts.first.id;
        final firstIndex = stream.indexOf(firstPostId);
        _hasMoreBefore = firstIndex > 0;

        final lastPostId = posts.last.id;
        final lastIndex = stream.indexOf(lastPostId);
        _hasMoreAfter = lastIndex < stream.length - 1;
      }

      return detail;
    });
  }

  /// 刷新当前话题详情（保持列表可见）
  Future<void> refreshWithPostNumber(int postNumber) async {
    if (state.isLoading) return;

    state = const AsyncLoading<TopicDetail>().copyWithPrevious(state);

    state = await AsyncValue.guard(() async {
      final service = ref.read(discourseServiceProvider);
      final detail = await service.getTopicDetail(arg.topicId, postNumber: postNumber);

      final posts = detail.postStream.posts;
      final stream = detail.postStream.stream;
      if (posts.isEmpty) {
        _hasMoreAfter = false;
        _hasMoreBefore = false;
      } else {
        final firstPostId = posts.first.id;
        final firstIndex = stream.indexOf(firstPostId);
        _hasMoreBefore = firstIndex > 0;

        final lastPostId = posts.last.id;
        final lastIndex = stream.indexOf(lastPostId);
        _hasMoreAfter = lastIndex < stream.length - 1;
      }

      return detail;
    });
  }

  /// 加载指定楼层的帖子（用于跳转）
  /// 返回加载后该帖子在列表中的索引，如果失败返回 -1
  Future<int> loadPostNumber(int postNumber) async {
    final currentDetail = state.value;
    if (currentDetail == null) return -1;

    final currentPosts = currentDetail.postStream.posts;

    // 先检查是否已加载
    final existingIndex = currentPosts.indexWhere((p) => p.postNumber == postNumber);
    if (existingIndex != -1) return existingIndex;

    try {
      final service = ref.read(discourseServiceProvider);
      final newDetail = await service.getTopicDetail(arg.topicId, postNumber: postNumber);

      // 合并帖子
      final existingIds = currentPosts.map((p) => p.id).toSet();
      final newPosts = newDetail.postStream.posts.where((p) => !existingIds.contains(p.id)).toList();
      final mergedPosts = [...currentPosts, ...newPosts];
      mergedPosts.sort((a, b) => a.postNumber.compareTo(b.postNumber));

      // 更新边界状态
      _hasMoreBefore = mergedPosts.first.postNumber > 1;
      _hasMoreAfter = mergedPosts.last.postNumber < currentDetail.postsCount;

      state = AsyncValue.data(TopicDetail(
        id: currentDetail.id,
        title: currentDetail.title,
        slug: currentDetail.slug,
        postsCount: currentDetail.postsCount,
        postStream: PostStream(posts: mergedPosts, stream: currentDetail.postStream.stream),
        categoryId: currentDetail.categoryId,
        closed: currentDetail.closed,
        archived: currentDetail.archived,
        tags: currentDetail.tags,
        views: currentDetail.views,
        likeCount: currentDetail.likeCount,
        createdAt: currentDetail.createdAt,
        visible: currentDetail.visible,
      ));

      // 返回目标帖子的索引
      return mergedPosts.indexWhere((p) => p.postNumber == postNumber);
    } catch (e) {
      print('[TopicDetail] 加载帖子 #$postNumber 失败: $e');
      return -1;
    }
  }
}

final topicDetailProvider = AsyncNotifierProvider.family.autoDispose<TopicDetailNotifier, TopicDetail, TopicDetailParams>(
  TopicDetailNotifier.new,
);

/// 话题 AI 摘要 Provider
/// 使用 autoDispose 在页面销毁时自动清理
/// family 参数为话题 ID
final topicSummaryProvider = FutureProvider.autoDispose
    .family<TopicSummary?, int>((ref, topicId) async {
  final service = ref.read(discourseServiceProvider);
  return service.getTopicSummary(topicId);
});
