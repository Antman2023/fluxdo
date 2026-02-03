import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/preferences_provider.dart';
import '../../services/emoji_handler.dart';
import '../mention/mention_autocomplete.dart';
import 'markdown_renderer.dart';
import 'markdown_toolbar.dart';
import 'package:pangutext/pangutext.dart';

/// 通用 Markdown 编辑器组件
/// 包含编辑/预览模式切换、工具栏和表情面板
class MarkdownEditor extends ConsumerStatefulWidget {
  /// 内容控制器（必需）
  final TextEditingController controller;
  
  /// 焦点节点（可选，不传则内部创建）
  final FocusNode? focusNode;
  
  /// 提示文本
  final String hintText;
  
  /// 最小行数（仅当 expands 为 false 时生效）
  final int minLines;
  
  /// 是否扩展填满可用空间
  final bool expands;
  
  /// 表情面板高度
  final double emojiPanelHeight;
  
  /// 表情面板状态变化回调
  final ValueChanged<bool>? onEmojiPanelChanged;

  /// 用户提及数据源（可选，不传则不启用 @用户 功能）
  final MentionDataSource? mentionDataSource;

  const MarkdownEditor({
    super.key,
    required this.controller,
    this.focusNode,
    this.hintText = '说点什么吧... (支持 Markdown)',
    this.minLines = 5,
    this.expands = false,
    this.emojiPanelHeight = 280.0,
    this.onEmojiPanelChanged,
    this.mentionDataSource,
  });

  @override
  ConsumerState<MarkdownEditor> createState() => MarkdownEditorState();
}

class MarkdownEditorState extends ConsumerState<MarkdownEditor> {
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;

  final _toolbarKey = GlobalKey<MarkdownToolbarState>();
  final _pangu = Pangu();
  bool _isApplyingPangu = false;

  bool _showPreview = false;
  String _previousText = '';

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
    EmojiHandler().init();
    _previousText = widget.controller.text;
    widget.controller.addListener(_handleTextChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChange);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  /// 处理文本变化，实现智能列表续行
  void _handleTextChange() {
    final currentText = widget.controller.text;
    final selection = widget.controller.selection;

    // 只在文本增加时处理
    if (currentText.length <= _previousText.length) {
      _previousText = currentText;
      return;
    }

    if (selection.isValid &&
        selection.start > 0 &&
        currentText[selection.start - 1] == '\n') {
      // 找到上一行的开始位置
      int prevLineStart = selection.start - 2;
      if (prevLineStart < 0) {
        _previousText = currentText;
        return;
      }

      // 向前查找上一行的开始
      while (prevLineStart > 0 && currentText[prevLineStart - 1] != '\n') {
        prevLineStart--;
      }

      // 提取上一行的内容
      final prevLine = currentText.substring(prevLineStart, selection.start - 1);

      // 检测无序列表：- item 或 * item 或 + item
      final unorderedMatch =
          RegExp(r'^(\s*)([-*+])\s+(.*)$').firstMatch(prevLine);
      if (unorderedMatch != null) {
        final indent = unorderedMatch.group(1)!;
        final marker = unorderedMatch.group(2)!;
        final content = unorderedMatch.group(3)!;

        if (content.isEmpty) {
          // 空列表项，移除列表标记
          final newText = currentText.replaceRange(
            prevLineStart,
            selection.start,
            '\n',
          );
          _previousText = newText;
          widget.controller.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: prevLineStart + 1),
          );
        } else {
          // 非空列表项，添加新的列表标记
          final prefix = '$indent$marker ';
          final newText = currentText.replaceRange(
            selection.start,
            selection.start,
            prefix,
          );
          _previousText = newText;
          widget.controller.value = TextEditingValue(
            text: newText,
            selection:
                TextSelection.collapsed(offset: selection.start + prefix.length),
          );
        }
        return;
      }

      // 检测有序列表：1. item
      final orderedMatch =
          RegExp(r'^(\s*)(\d+)\.\s+(.*)$').firstMatch(prevLine);
      if (orderedMatch != null) {
        final indent = orderedMatch.group(1)!;
        final number = int.parse(orderedMatch.group(2)!);
        final content = orderedMatch.group(3)!;

        if (content.isEmpty) {
          // 空列表项，移除列表标记
          final newText = currentText.replaceRange(
            prevLineStart,
            selection.start,
            '\n',
          );
          _previousText = newText;
          widget.controller.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: prevLineStart + 1),
          );
        } else {
          // 非空列表项，添加新的列表标记（数字递增）
          final prefix = '$indent${number + 1}. ';
          final newText = currentText.replaceRange(
            selection.start,
            selection.start,
            prefix,
          );
          _previousText = newText;
          widget.controller.value = TextEditingValue(
            text: newText,
            selection:
                TextSelection.collapsed(offset: selection.start + prefix.length),
          );
        }
        return;
      }
    }

    if (ref.read(preferencesProvider).autoPanguSpacing &&
        !_isApplyingPangu &&
        (widget.controller.value.composing.isValid &&
            !widget.controller.value.composing.isCollapsed)) {
      _previousText = currentText;
      return;
    }

    if (ref.read(preferencesProvider).autoPanguSpacing &&
        !_isApplyingPangu &&
        selection.isValid) {
      final panguText = _pangu.spacingText(currentText);
      if (panguText != currentText) {
        _isApplyingPangu = true;
        final cursor = selection.start.clamp(0, currentText.length);
        final prefix = currentText.substring(0, cursor);
        final newCursor = _pangu.spacingText(prefix).length;
        final clampedCursor = newCursor.clamp(0, panguText.length);
        widget.controller.value = TextEditingValue(
          text: panguText,
          selection: TextSelection.collapsed(offset: clampedCursor),
        );
        _previousText = panguText;
        _isApplyingPangu = false;
        return;
      }
    }

    _previousText = currentText;
  }
  
  void _togglePreview() {
    setState(() {
      _showPreview = !_showPreview;
      if (_showPreview) {
        FocusScope.of(context).unfocus();
        _toolbarKey.currentState?.closeEmojiPanel();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusNode.requestFocus();
        });
      }
    });
  }
  
  /// 关闭表情面板（供外部调用）
  void closeEmojiPanel() {
    _toolbarKey.currentState?.closeEmojiPanel();
  }
  
  /// 请求焦点
  void requestFocus() {
    _focusNode.requestFocus();
  }
  
  /// 当前是否显示表情面板
  bool get showEmojiPanel => _toolbarKey.currentState?.showEmojiPanel ?? false;

  void _applyPanguSpacing() {
    if (_isApplyingPangu) return;
    final currentText = widget.controller.text;
    final selection = widget.controller.selection;
    if (currentText.isEmpty || !selection.isValid) return;
    if (widget.controller.value.composing.isValid &&
        !widget.controller.value.composing.isCollapsed) {
      return;
    }

    final spacedText = _pangu.spacingText(currentText);
    if (spacedText == currentText) return;

    _isApplyingPangu = true;
    final cursor = selection.start.clamp(0, currentText.length);
    final prefix = currentText.substring(0, cursor);
    final newCursor = _pangu.spacingText(prefix).length;
    final clampedCursor = newCursor.clamp(0, spacedText.length);
    widget.controller.value = TextEditingValue(
      text: spacedText,
      selection: TextSelection.collapsed(offset: clampedCursor),
    );
    _previousText = spacedText;
    _isApplyingPangu = false;
  }

  /// 构建文本编辑器（可选包含 @提及自动补全）
  Widget _buildTextEditor() {
    final textField = TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      maxLines: null,
      minLines: widget.expands ? null : widget.minLines,
      expands: widget.expands,
      textAlignVertical: TextAlignVertical.top,
      keyboardType: TextInputType.multiline,
      decoration: InputDecoration(
        hintText: widget.hintText,
        border: InputBorder.none,
      ),
      onTap: () {
        _toolbarKey.currentState?.closeEmojiPanel();
      },
    );

    // 如果提供了 mentionDataSource，则包裹 MentionAutocomplete
    if (widget.mentionDataSource != null) {
      return MentionAutocomplete(
        controller: widget.controller,
        focusNode: _focusNode,
        dataSource: widget.mentionDataSource!,
        child: textField,
      );
    }

    return textField;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      children: [
        // 编辑/预览区域
        Expanded(
          child: _showPreview
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: widget.controller.text.isEmpty
                      ? Text(
                          '（无内容）',
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                        )
                      : MarkdownBody(data: widget.controller.text),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildTextEditor(),
                ),
        ),
        
        // 工具栏
        MarkdownToolbar(
          key: _toolbarKey,
          controller: widget.controller,
          focusNode: _focusNode,
          isPreview: _showPreview,
          onTogglePreview: _togglePreview,
          onApplyPangu: _applyPanguSpacing,
          showPanguButton: true,
          emojiPanelHeight: widget.emojiPanelHeight,
        ),
      ],
    );
  }
}
