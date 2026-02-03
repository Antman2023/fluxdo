import 'dart:async';
import 'package:flutter/foundation.dart';

/// 帖子高亮状态控制器
/// 负责管理帖子的高亮动画效果
class PostHighlightController extends ChangeNotifier {
  int? _highlightPostNumber;
  Timer? _highlightTimer;

  /// 高亮帖子号 ValueNotifier（用于隔离 UI 更新）
  final ValueNotifier<int?> highlightNotifier = ValueNotifier<int?>(null);

  /// 当前高亮的帖子号
  int? get highlightPostNumber => _highlightPostNumber;

  /// 待高亮的帖子号（等待列表可见后触发）
  int? pendingHighlightPostNumber;

  /// 是否跳过下一次跳转高亮
  bool skipNextJumpHighlight = false;

  /// 触发高亮效果
  void triggerHighlight(int postNumber) {
    _highlightPostNumber = postNumber;
    highlightNotifier.value = postNumber;

    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      _highlightPostNumber = null;
      highlightNotifier.value = null;
    });
  }

  /// 清除高亮
  void clearHighlight() {
    _highlightTimer?.cancel();
    _highlightPostNumber = null;
    pendingHighlightPostNumber = null;
    highlightNotifier.value = null;
  }

  /// 消费待高亮帖子号并触发高亮
  void consumePendingHighlight() {
    if (pendingHighlightPostNumber != null) {
      final target = pendingHighlightPostNumber!;
      pendingHighlightPostNumber = null;
      skipNextJumpHighlight = false;
      triggerHighlight(target);
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    highlightNotifier.dispose();
    super.dispose();
  }
}
