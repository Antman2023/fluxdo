import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification.dart';
import '../utils/pagination_helper.dart';
import 'core_providers.dart';
import 'message_bus_providers.dart';

/// 通知列表 Notifier (支持分页和刷新)
class NotificationListNotifier extends AsyncNotifier<List<DiscourseNotification>> {
  int _totalRows = 0;
  bool get hasMore => state.value != null && state.value!.length < _totalRows;

  /// 分页助手
  static final _paginationHelper = PaginationHelpers.forNotifications<DiscourseNotification>(
    keyExtractor: (n) => n.id,
  );

  @override
  Future<List<DiscourseNotification>> build() async {
    final service = ref.read(discourseServiceProvider);
    final response = await service.getNotifications();
    _totalRows = response.totalRowsNotifications;
    return response.notifications;
  }

  /// 刷新列表
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(discourseServiceProvider);
      final response = await service.getNotifications();
      _totalRows = response.totalRowsNotifications;
      return response.notifications;
    });
  }

  /// 静默刷新
  Future<void> silentRefresh() async {
    final service = ref.read(discourseServiceProvider);
    try {
      final response = await service.getNotifications();
      _totalRows = response.totalRowsNotifications;
      state = AsyncValue.data(response.notifications);
    } catch (e) {
      debugPrint('Silent refresh notifications failed: $e');
    }
  }

  /// 加载更多
  Future<void> loadMore() async {
    if (!hasMore || state.isLoading) return;

    // ignore: invalid_use_of_internal_member
    state = const AsyncLoading<List<DiscourseNotification>>().copyWithPrevious(state);

    state = await AsyncValue.guard(() async {
      final currentList = state.requireValue;
      final offset = currentList.length;

      final service = ref.read(discourseServiceProvider);
      final response = await service.getNotifications(offset: offset);

      final currentState = PaginationState(items: currentList);
      final result = _paginationHelper.processLoadMore(
        currentState,
        PaginationResult(items: response.notifications, totalRows: _totalRows),
      );

      return result.items;
    });
  }

  /// 标记所有为已读
  Future<void> markAllAsRead() async {
    final service = ref.read(discourseServiceProvider);
    await service.markAllNotificationsRead();

    // 重置通知计数（复刻 Discourse 原项目逻辑）
    ref.read(notificationCountStateProvider.notifier).markAllRead();

    // 更新本地状态
    state.whenData((list) {
      state = AsyncValue.data(
        list.map((n) => DiscourseNotification(
          id: n.id,
          userId: n.userId,
          notificationType: n.notificationType,
          read: true,
          highPriority: n.highPriority,
          createdAt: n.createdAt,
          postNumber: n.postNumber,
          topicId: n.topicId,
          slug: n.slug,
          data: n.data,
          fancyTitle: n.fancyTitle,
          actingUserAvatarTemplate: n.actingUserAvatarTemplate,
        )).toList(),
      );
    });
  }

  /// 标记单个通知为已读
  void markAsRead(int notificationId) {
    state.whenData((list) {
      state = AsyncValue.data(
        list.map((n) {
          if (n.id == notificationId) {
            return DiscourseNotification(
              id: n.id,
              userId: n.userId,
              notificationType: n.notificationType,
              read: true,
              highPriority: n.highPriority,
              createdAt: n.createdAt,
              postNumber: n.postNumber,
              topicId: n.topicId,
              slug: n.slug,
              data: n.data,
              fancyTitle: n.fancyTitle,
              actingUserAvatarTemplate: n.actingUserAvatarTemplate,
            );
          }
          return n;
        }).toList(),
      );
    });
  }

  /// 添加新通知（用于 MessageBus 推送）
  void addNotification(DiscourseNotification notification) {
    final currentList = state.value;
    if (currentList == null) return;

    // 检查是否已存在
    if (currentList.any((n) => n.id == notification.id)) return;

    // 插入到列表开头
    state = AsyncValue.data([notification, ...currentList]);
  }
}

final notificationListProvider = AsyncNotifierProvider<NotificationListNotifier, List<DiscourseNotification>>(() {
  return NotificationListNotifier();
});

/// 未读通知数量 Provider
/// 优先使用服务端推送的计数器（复刻 Discourse 原项目逻辑）
final unreadNotificationCountProvider = Provider<int>((ref) {
  final countState = ref.watch(notificationCountStateProvider);
  return countState.allUnread;
});
