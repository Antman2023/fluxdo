import 'package:flutter/material.dart';

/// 链接插入对话框
/// 返回 {text: '链接文本', url: 'https://...'}
class LinkInsertDialog extends StatefulWidget {
  final String? initialText;
  final String? initialUrl;

  const LinkInsertDialog({
    super.key,
    this.initialText,
    this.initialUrl,
  });

  @override
  State<LinkInsertDialog> createState() => _LinkInsertDialogState();
}

class _LinkInsertDialogState extends State<LinkInsertDialog> {
  late final TextEditingController _textController;
  late final TextEditingController _urlController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText);
    _urlController = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _textController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop({
        'text': _textController.text,
        'url': _urlController.text,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('插入链接'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _textController,
              decoration: const InputDecoration(
                labelText: '链接文本',
                hintText: '显示的文字',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入链接文本';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://example.com',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入 URL';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 显示链接插入对话框
Future<Map<String, String>?> showLinkInsertDialog(
  BuildContext context, {
  String? initialText,
  String? initialUrl,
}) {
  return showDialog<Map<String, String>>(
    context: context,
    builder: (context) => LinkInsertDialog(
      initialText: initialText,
      initialUrl: initialUrl,
    ),
  );
}
