import 'package:flutter/material.dart';

import 'theme.dart';

/// 搜尋頁面的輸入框：直接呼叫電視系統輸入法（支援中文注音、語音搜尋與手機遙控輸入）。
class TvKeyboard extends StatefulWidget {
  const TvKeyboard({
    super.key,
    required this.text,
    required this.onChanged,
    required this.onSubmit,
    this.focusNode,
    this.inputFocusNode,
  });

  final String text;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmit;
  final FocusNode? focusNode;
  final FocusNode? inputFocusNode;

  @override
  State<TvKeyboard> createState() => _TvKeyboardState();
}

class _TvKeyboardState extends State<TvKeyboard> {
  static const double _boxWidth = 608.0;

  late final TextEditingController _controller;
  late final FocusNode _internalInputFocus;
  FocusNode get _inputFocus => widget.inputFocusNode ?? widget.focusNode ?? _internalInputFocus;

  bool _inputFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
    _internalInputFocus = FocusNode();
    _inputFocus.addListener(_onInputFocusChange);
  }

  void _onInputFocusChange() {
    if (mounted) {
      setState(() => _inputFocused = _inputFocus.hasFocus);
    }
  }

  @override
  void didUpdateWidget(covariant TvKeyboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldFocus = oldWidget.inputFocusNode ?? oldWidget.focusNode ?? _internalInputFocus;
    if (oldFocus != _inputFocus) {
      oldFocus.removeListener(_onInputFocusChange);
      _inputFocus.addListener(_onInputFocusChange);
    }
    if (_controller.text != widget.text) {
      _controller.value = TextEditingValue(
        text: widget.text,
        selection: TextSelection.collapsed(offset: widget.text.length),
      );
    }
  }

  @override
  void dispose() {
    _inputFocus.removeListener(_onInputFocusChange);
    _controller.dispose();
    _internalInputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _boxWidth,
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _inputFocused ? const Color(0x18FFFFFF) : Colors.transparent,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(
          bottom: BorderSide(color: _inputFocused ? Tv.focusBg : const Color(0xFF555555), width: _inputFocused ? 4 : 3),
        ),
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Icon(Icons.search, size: 32, color: _inputFocused ? Tv.focusBg : const Color(0xFF777777)),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _inputFocus,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmit,
              textInputAction: TextInputAction.search,
              cursorColor: Tv.focusBg,
              style: const TextStyle(fontSize: 36, color: Tv.text),
              decoration: const InputDecoration(
                hintText: '搜尋 YouTube',
                hintStyle: TextStyle(fontSize: 30, color: Color(0xFF777777)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (widget.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, color: Tv.text2, size: 28),
              tooltip: '清除',
              onPressed: () {
                widget.onChanged('');
                _inputFocus.requestFocus();
              },
            ),
        ],
      ),
    );
  }
}
