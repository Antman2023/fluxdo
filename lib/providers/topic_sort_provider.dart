// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'topic_list_provider.dart';

/// 当前排序模式（不持久化，每次启动默认 latest）
final topicSortProvider = StateProvider<TopicListFilter>((ref) => TopicListFilter.latest);

/// 每个 tab 独立的标签筛选（categoryId -> tags）
/// null 表示"全部"tab
final tabTagsProvider = StateProvider.family<List<String>, int?>((ref, categoryId) => []);
