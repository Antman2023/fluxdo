import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/topic.dart';
import 'core_providers.dart';

/// 浏览历史 Notifier (支持分页)
class BrowsingHistoryNotifier extends AsyncNotifier<List<Topic>> {
  int _page = 0;
  bool _hasMore = true;
  bool get hasMore => _hasMore;

  @override
  Future<List<Topic>> build() async {
    _page = 0;
    _hasMore = true;
    final service = ref.read(discourseServiceProvider);
    final response = await service.getBrowsingHistory(page: 0);
    if (response.topics.isEmpty) _hasMore = false;
    return response.topics;
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      _page = 0;
      _hasMore = true;
      final service = ref.read(discourseServiceProvider);
      final response = await service.getBrowsingHistory(page: 0);
      if (response.topics.isEmpty) _hasMore = false;
      return response.topics;
    });
  }

  Future<void> loadMore() async {
    if (!_hasMore || state.isLoading) return;

    state = const AsyncLoading<List<Topic>>().copyWithPrevious(state);

    state = await AsyncValue.guard(() async {
      final currentList = state.requireValue;
      final nextPage = _page + 1;

      final service = ref.read(discourseServiceProvider);
      final response = await service.getBrowsingHistory(page: nextPage);

      if (response.topics.isEmpty) {
        _hasMore = false;
        return currentList;
      }

      _page = nextPage;

      // 去重
      final newItems = response.topics
          .where((t) => !currentList.any((c) => c.id == t.id))
          .toList();

      return [...currentList, ...newItems];
    });
  }
}

final browsingHistoryProvider = AsyncNotifierProvider.autoDispose<BrowsingHistoryNotifier, List<Topic>>(() {
  return BrowsingHistoryNotifier();
});

/// 书签 Notifier (支持分页)
class BookmarksNotifier extends AsyncNotifier<List<Topic>> {
  int _page = 0;
  bool _hasMore = true;
  bool get hasMore => _hasMore;

  @override
  Future<List<Topic>> build() async {
    _page = 0;
    _hasMore = true;
    final service = ref.read(discourseServiceProvider);
    final response = await service.getUserBookmarks(page: 0);
    if (response.topics.isEmpty) _hasMore = false;
    return response.topics;
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      _page = 0;
      _hasMore = true;
      final service = ref.read(discourseServiceProvider);
      final response = await service.getUserBookmarks(page: 0);
      if (response.topics.isEmpty) _hasMore = false;
      return response.topics;
    });
  }

  Future<void> loadMore() async {
    if (!_hasMore || state.isLoading) return;

    state = const AsyncLoading<List<Topic>>().copyWithPrevious(state);

    state = await AsyncValue.guard(() async {
      final currentList = state.requireValue;
      final nextPage = _page + 1;

      final service = ref.read(discourseServiceProvider);
      final response = await service.getUserBookmarks(page: nextPage);

      if (response.topics.isEmpty) {
        _hasMore = false;
        return currentList;
      }

      _page = nextPage;

      // 去重
      final newItems = response.topics
          .where((t) => !currentList.any((c) => c.id == t.id))
          .toList();

      return [...currentList, ...newItems];
    });
  }
}

final bookmarksProvider = AsyncNotifierProvider.autoDispose<BookmarksNotifier, List<Topic>>(() {
  return BookmarksNotifier();
});

/// 我的话题 Notifier (支持分页)
class MyTopicsNotifier extends AsyncNotifier<List<Topic>> {
  int _page = 0;
  bool _hasMore = true;
  bool get hasMore => _hasMore;

  @override
  Future<List<Topic>> build() async {
    _page = 0;
    _hasMore = true;
    final service = ref.read(discourseServiceProvider);
    final response = await service.getUserCreatedTopics(page: 0);
    if (response.topics.isEmpty) _hasMore = false;
    return response.topics;
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      _page = 0;
      _hasMore = true;
      final service = ref.read(discourseServiceProvider);
      final response = await service.getUserCreatedTopics(page: 0);
      if (response.topics.isEmpty) _hasMore = false;
      return response.topics;
    });
  }

  Future<void> loadMore() async {
    if (!_hasMore || state.isLoading) return;

    state = const AsyncLoading<List<Topic>>().copyWithPrevious(state);

    state = await AsyncValue.guard(() async {
      final currentList = state.requireValue;
      final nextPage = _page + 1;

      final service = ref.read(discourseServiceProvider);
      final response = await service.getUserCreatedTopics(page: nextPage);

      if (response.topics.isEmpty) {
        _hasMore = false;
        return currentList;
      }

      _page = nextPage;

      // 去重
      final newItems = response.topics
          .where((t) => !currentList.any((c) => c.id == t.id))
          .toList();

      return [...currentList, ...newItems];
    });
  }
}

final myTopicsProvider = AsyncNotifierProvider.autoDispose<MyTopicsNotifier, List<Topic>>(() {
  return MyTopicsNotifier();
});
