import 'package:flutter/material.dart';
import '../discourse_html_content_widget.dart';
import 'scan_boundary.dart';

/// 构建自定义 table widget
Widget? buildTable({
  required BuildContext context,
  required ThemeData theme,
  required dynamic element,
  List<String>? galleryImages,
  bool screenshotMode = false,
}) {
  // 解析 table 结构
  final rows = <List<_TableCellData>>[];

  // 查找 thead 和 tbody
  final theadElements = element.getElementsByTagName('thead');
  final tbodyElements = element.getElementsByTagName('tbody');
  final directTrElements = element.getElementsByTagName('tr');

  // 解析 thead
  if (theadElements.isNotEmpty) {
    final thead = theadElements.first;
    for (final tr in thead.getElementsByTagName('tr')) {
      rows.add(_parseRow(tr, isHeader: true));
    }
  }

  // 解析 tbody
  if (tbodyElements.isNotEmpty) {
    final tbody = tbodyElements.first;
    for (final tr in tbody.getElementsByTagName('tr')) {
      rows.add(_parseRow(tr, isHeader: false));
    }
  } else if (theadElements.isEmpty) {
    // 没有 thead 和 tbody，直接解析 tr
    for (final tr in directTrElements) {
      rows.add(_parseRow(tr, isHeader: false));
    }
  }

  if (rows.isEmpty) return null;

  // 计算列数
  final columnCount = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
  if (columnCount == 0) return null;

  // 构建 table widget
  // 用 ScanBoundary 包裹，阻止外层 overlay 扫描进入表格
  // 表格单元格内部的 DiscourseHtmlContent 有自己的 overlay 处理
  final tableWidget = Container(
    margin: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      border: Border.all(
        color: theme.colorScheme.outlineVariant,
        width: 1,
      ),
      borderRadius: BorderRadius.circular(8),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder(
          horizontalInside: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 1,
          ),
          verticalInside: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        children: rows.asMap().entries.map((entry) {
          final rowIndex = entry.key;
          final row = entry.value;
          final isFirstRow = rowIndex == 0;

          return TableRow(
            decoration: isFirstRow && row.any((c) => c.isHeader)
                ? BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                  )
                : null,
            children: List.generate(columnCount, (colIndex) {
              if (colIndex < row.length) {
                return _buildCell(context, theme, row[colIndex], galleryImages, screenshotMode: screenshotMode);
              }
              return const SizedBox.shrink();
            }),
          );
        }).toList(),
      ),
    ),
  );

  // 截图模式下用 FittedBox 缩放，确保宽表格完整显示不被截断
  if (screenshotMode) {
    return ScanBoundary(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: tableWidget,
      ),
    );
  }

  return ScanBoundary(
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: tableWidget,
    ),
  );
}

/// 解析表格行
List<_TableCellData> _parseRow(dynamic tr, {required bool isHeader}) {
  final cells = <_TableCellData>[];

  // 查找 th 和 td
  for (final child in tr.children) {
    if (child.localName == 'th' || child.localName == 'td') {
      cells.add(_TableCellData(
        element: child,
        isHeader: child.localName == 'th' || isHeader,
      ));
    }
  }

  return cells;
}

/// 构建单元格
Widget _buildCell(BuildContext context, ThemeData theme, _TableCellData cellData, List<String>? galleryImages, {bool screenshotMode = false}) {
  final element = cellData.element;
  // 获取单元格的 innerHTML，使用 DiscourseHtmlContent 渲染
  final innerHtml = element.innerHtml ?? '';

  final content = DiscourseHtmlContent(
    html: innerHtml,
    compact: true,
    galleryImages: galleryImages,
    screenshotMode: screenshotMode,
  );

  // 截图模式下不限制单元格宽度
  if (screenshotMode) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: content,
    );
  }

  return Padding(
    padding: const EdgeInsets.all(8),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: content,
    ),
  );
}

/// 表格单元格数据
class _TableCellData {
  final dynamic element;
  final bool isHeader;

  _TableCellData({
    required this.element,
    required this.isHeader,
  });
}
