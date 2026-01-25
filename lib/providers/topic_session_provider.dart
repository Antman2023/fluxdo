import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 话题会话状态（仅在当前会话有效）
/// 用于记录本次阅读过程中哪些帖子被标记为已读（通过 Timings 上报）
class TopicSessionState {
  /// 本次会话中已读的帖子编号集合
  final Set<int> readPostNumbers;

  const TopicSessionState({
    this.readPostNumbers = const {},
  });

  TopicSessionState copyWith({
    Set<int>? readPostNumbers,
  }) {
    return TopicSessionState(
      readPostNumbers: readPostNumbers ?? this.readPostNumbers,
    );
  }
}

class TopicSessionNotifier extends Notifier<TopicSessionState> {
  final int topicId;
  
  TopicSessionNotifier(this.topicId);

  @override
  TopicSessionState build() {
    return const TopicSessionState();
  }

  /// 标记帖子为已读（添加到已读集合）
  void markAsRead(Set<int> postNumbers) {
    if (postNumbers.isEmpty) return;
    
    final newRead = {...state.readPostNumbers, ...postNumbers};
    if (newRead.length != state.readPostNumbers.length) {
      state = state.copyWith(readPostNumbers: newRead);
    }
  }
}

/// 话题会话状态 Provider
/// family 参数为 topicId
final topicSessionProvider = NotifierProvider.family<TopicSessionNotifier, TopicSessionState, int>(
  TopicSessionNotifier.new,
);
