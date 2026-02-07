import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'inline_spoiler_builder.dart' show spoilerMarkerFont;

/// 用于标记内联代码的特殊字体名称
const String _codeMarkerFont = '_InlineCode_';

/// 检查样式是否是内联代码
bool isCodeMarkerStyle(TextStyle? style) {
  if (style == null) return false;

  // 检查 fontFamily 和 fontFamilyFallback
  final fontFamily = style.fontFamily ?? '';
  final fallback = style.fontFamilyFallback ?? [];

  if (fontFamily.contains(_codeMarkerFont)) return true;
  for (final f in fallback) {
    if (f.contains(_codeMarkerFont)) return true;
  }
  return false;
}

/// 获取内联代码的 CSS 样式
Map<String, String> getInlineCodeStyles(bool isDark, {bool isInSpoiler = false}) {
  // 如果在 spoiler 内，需要同时包含 spoiler 标记
  final fontFamily = isInSpoiler
      ? '$spoilerMarkerFont, $_codeMarkerFont, FiraCode, monospace'
      : '$_codeMarkerFont, FiraCode, monospace';
  return {
    'font-family': fontFamily,
    'background-color': '#00000000', // 透明背景，由 overlay 绘制
    'color': isDark ? '#b0b0b0' : '#666666',
    'font-size': '0.85em',
  };
}

/// 构建 click-count Widget（直接 WidgetSpan 渲染）
Widget buildClickCountWidget({
  required String count,
  required bool isDark,
}) {
  final bgColor = isDark ? const Color(0xFF3a3d47) : const Color(0xFFe8ebef);
  final textColor = isDark ? const Color(0xFF9ca3af) : const Color(0xFF6b7280);

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      count,
      style: TextStyle(
        color: textColor,
        fontSize: 10,
      ),
    ),
  );
}

/// 内联代码背景覆盖层 Widget
class InlineDecoratorOverlay extends StatefulWidget {
  final Widget child;

  const InlineDecoratorOverlay({
    super.key,
    required this.child,
  });

  @override
  State<InlineDecoratorOverlay> createState() => _InlineDecoratorOverlayState();
}

class _InlineDecoratorOverlayState extends State<InlineDecoratorOverlay> {
  // 内联代码组列表（每组是一个 code 元素的多行矩形）
  final List<List<Rect>> _codeGroups = [];
  bool _hasScanned = false;

  @override
  void didUpdateWidget(InlineDecoratorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != widget.child) {
      _hasScanned = false;
      _codeGroups.clear();
    }
  }

  void _scanForCodeRects() {
    _codeGroups.clear();

    final renderObject = context.findRenderObject();
    if (renderObject == null) return;

    _visitRenderObject(renderObject, Offset.zero);
  }

  void _visitRenderObject(RenderObject renderObject, Offset parentOffset) {
    if (renderObject is RenderParagraph) {
      _extractCodeRects(renderObject, parentOffset);
    }

    renderObject.visitChildren((child) {
      Offset childOffset = parentOffset;
      if (child is RenderBox && renderObject is RenderBox) {
        final parentData = child.parentData;
        if (parentData is BoxParentData) {
          childOffset = parentOffset + parentData.offset;
        }
      }
      _visitRenderObject(child, childOffset);
    });
  }

  void _extractCodeRects(RenderParagraph paragraph, Offset offset) {
    final text = paragraph.text;
    _visitInlineSpan(text, paragraph, offset, 0, null);
  }

  int _visitInlineSpan(
    InlineSpan span,
    RenderParagraph paragraph,
    Offset offset,
    int charIndex,
    TextStyle? parentStyle,
  ) {
    if (span is TextSpan) {
      final effectiveStyle = parentStyle?.merge(span.style) ?? span.style;
      final textLength = span.text?.length ?? 0;

      // 检测内联代码
      if (textLength > 0 && isCodeMarkerStyle(effectiveStyle)) {
        try {
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: charIndex, extentOffset: charIndex + textLength),
          );

          // 收集同一个 code 元素的所有矩形作为一组
          final rects = <Rect>[];
          for (final box in boxes) {
            final rect = Rect.fromLTRB(
              offset.dx + box.left,
              offset.dy + box.top,
              offset.dx + box.right,
              offset.dy + box.bottom,
            );

            if (rect.width > 0 && rect.height > 0) {
              rects.add(rect);
            }
          }
          if (rects.isNotEmpty) {
            _codeGroups.add(rects);
          }
        } catch (e) {
          // 忽略错误
        }
      }

      charIndex += textLength;

      if (span.children != null) {
        for (final child in span.children!) {
          charIndex = _visitInlineSpan(child, paragraph, offset, charIndex, effectiveStyle);
        }
      }
    } else if (span is WidgetSpan) {
      charIndex += 1;
    }

    return charIndex;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Stack(
      children: [
        // 背景层在下面（ClipRect 防止溢出）
        if (_codeGroups.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: CustomPaint(
                  painter: _InlineCodePainter(
                    groups: _codeGroups,
                    isDark: isDark,
                  ),
                ),
              ),
            ),
          ),
        // 内容层在上面
        NotificationListener<SizeChangedLayoutNotification>(
          onNotification: (_) {
            // 布局变化时重新扫描
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _scanForCodeRects();
                setState(() {});
              }
            });
            return false;
          },
          child: SizeChangedLayoutNotifier(
            child: Builder(
              builder: (context) {
                // 首次构建后延迟扫描
                if (!_hasScanned) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _scanForCodeRects();
                      _hasScanned = true;
                      setState(() {});
                    }
                  });
                }
                return widget.child;
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// 内联代码背景绘制器
class _InlineCodePainter extends CustomPainter {
  final List<List<Rect>> groups;
  final bool isDark;

  _InlineCodePainter({
    required this.groups,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgColor = isDark ? const Color(0xFF3a3a3a) : const Color(0xFFe8e8e8);
    const radius = 3.0;
    const hPadding = 4.0; // 和 code-spacer 宽度一致

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = bgColor;

    for (final group in groups) {
      final count = group.length;

      for (int i = 0; i < count; i++) {
        final rect = group[i];
        final isFirst = i == 0;
        final isLast = i == count - 1;

        // 背景向外扩展到 spacer 位置
        final paddedRect = Rect.fromLTRB(
          rect.left - hPadding,
          rect.top,
          rect.right + hPadding,
          rect.bottom,
        );

        // 根据位置决定圆角
        // 单行：四角都有圆角
        // 多行第一行：左边有圆角，右边没有
        // 多行最后一行：左边没有圆角，右边有圆角
        // 多行中间行：都没有圆角
        final Radius leftRadius = isFirst ? const Radius.circular(radius) : Radius.zero;
        final Radius rightRadius = isLast ? const Radius.circular(radius) : Radius.zero;

        final rrect = RRect.fromRectAndCorners(
          paddedRect,
          topLeft: leftRadius,
          bottomLeft: leftRadius,
          topRight: rightRadius,
          bottomRight: rightRadius,
        );
        canvas.drawRRect(rrect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_InlineCodePainter oldDelegate) => true;
}
