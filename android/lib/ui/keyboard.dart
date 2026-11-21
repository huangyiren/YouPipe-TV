import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'focusable.dart';
import 'theme.dart';

/// A key: what it types or does, and how many of the 7 columns it spans.
class _Key {
  const _Key(this.label, this.span, {this.icon, this.action});

  final String label;
  final int span;
  final IconData? icon;
  final String? action; // null: types [label]
}

/// 搜尋頁面的鍵盤：上方為支援系統輸入法（中文/語音/手機輸入）的輸入框，
/// 下方為 7 欄式 TV 虛擬鍵盤（空白、退格、123、清除、搜尋）。
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
  static const _letters = ['abcdefg', 'hijklmn', 'opqrstu', "vwxyz-'"];
  static const _symbols = ['1234567', '890&#()', '@!?:~.,', r'/$%+=_"'];
  static const _cell = 80.0;
  static const _gapSize = 8.0;
  static const double _keyboardWidth = 7 * _cell + 6 * _gapSize; // 608.0

  late final TextEditingController _controller;
  late final FocusNode _internalInputFocus;
  FocusNode get _inputFocus => widget.inputFocusNode ?? _internalInputFocus;

  bool _symbolMode = false;
  int _row = 0;
  int _col = 0; // key index within the row
  bool _focused = false;
  bool _inputFocused = false;
  late final _select = SelectHandler(_press, null);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
    _internalInputFocus = FocusNode();
  }

  @override
  void didUpdateWidget(covariant TvKeyboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.text) {
      _controller.value = TextEditingValue(
        text: widget.text,
        selection: TextSelection.collapsed(offset: widget.text.length),
      );
    }
  }

  List<List<_Key>> get _rows => [
    for (final r in (_symbolMode ? _symbols : _letters)) [for (final c in r.split('')) _Key(c, 1)],
    [
      const _Key('空白', 3, icon: Icons.space_bar, action: 'space'),
      const _Key('', 2, icon: Icons.backspace_outlined, action: 'back'),
      _Key(_symbolMode ? 'ABC' : '123', 2, action: 'mode'),
    ],
    [const _Key('清除', 2, action: 'clear'), const _Key('搜尋', 5, icon: Icons.search, action: 'search')],
  ];

  int _startColumn(List<_Key> row, int index) => row.take(index).fold(0, (a, k) => a + k.span);

  /// The key in [row] that covers column [column].
  int _keyAt(List<_Key> row, int column) {
    var c = 0;
    for (var i = 0; i < row.length; i++) {
      c += row[i].span;
      if (column < c) return i;
    }
    return row.length - 1;
  }

  void _press() {
    final k = _rows[_row][_col];
    final t = widget.text;
    switch (k.action) {
      case 'space':
        widget.onChanged('$t ');
      case 'back':
        if (t.isNotEmpty) widget.onChanged(t.substring(0, t.length - 1));
      case 'mode':
        setState(() => _symbolMode = !_symbolMode);
      case 'clear':
        widget.onChanged('');
      case 'search':
        widget.onSubmit(t);
      default:
        if (t.length < 100) widget.onChanged('$t${k.label}');
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyDownEvent || e is KeyRepeatEvent) {
      final rows = _rows;
      final k = e.logicalKey;
      if (k == LogicalKeyboardKey.arrowLeft) {
        if (_col == 0) return KeyEventResult.ignored;
        setState(() => _col--);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowRight) {
        if (_col >= rows[_row].length - 1) return KeyEventResult.ignored;
        setState(() => _col++);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp) {
        if (_row == 0) {
          // 在第一排按上方向鍵，將焦點移到上方的系統中文輸入框
          _inputFocus.requestFocus();
          return KeyEventResult.handled;
        }
        final to = _row - 1;
        final column = _startColumn(rows[_row], _col);
        setState(() {
          _col = _keyAt(rows[to], column);
          _row = to;
        });
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowDown) {
        if (_row >= rows.length - 1) return KeyEventResult.ignored;
        final to = _row + 1;
        final column = _startColumn(rows[_row], _col);
        setState(() {
          _col = _keyAt(rows[to], column);
          _row = to;
        });
        return KeyEventResult.handled;
      }
      // 實體鍵盤直接輸入
      final ch = e.character;
      if (ch != null && ch.length == 1 && ch.codeUnitAt(0) >= 32 && !isSelectKey(k)) {
        widget.onChanged('${widget.text}$ch');
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.backspace) {
        if (widget.text.isNotEmpty) widget.onChanged(widget.text.substring(0, widget.text.length - 1));
        return KeyEventResult.handled;
      }
    }
    return _select.handle(e);
  }

  @override
  void dispose() {
    _select.dispose();
    _controller.dispose();
    _internalInputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 支援系統中文輸入法、語音與手機遙控輸入的原生 TextField
        Container(
          width: _keyboardWidth,
          height: 80,
          margin: const EdgeInsets.only(bottom: 28),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _inputFocused ? const Color(0x18FFFFFF) : Colors.transparent,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border(
              bottom: BorderSide(
                color: _inputFocused ? Tv.focusBg : const Color(0xFF555555),
                width: _inputFocused ? 4 : 3,
              ),
            ),
          ),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Icon(Icons.keyboard, size: 32, color: _inputFocused ? Tv.focusBg : const Color(0xFF777777)),
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
                    hintText: '搜尋 YouTube（支援中文輸入）',
                    hintStyle: TextStyle(fontSize: 30, color: Color(0xFF777777)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
        // 下方 7 欄式 TV 虛擬鍵盤
        Focus(
          focusNode: widget.focusNode,
          onFocusChange: (f) => setState(() => _focused = f),
          onKeyEvent: _onKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var r = 0; r < rows.length; r++)
                Padding(
                  padding: const EdgeInsets.only(bottom: _gapSize),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < rows[r].length; i++) ...[
                        if (i > 0) const SizedBox(width: _gapSize),
                        _keyView(rows[r][i], _focused && r == _row && i == _col, () {
                          setState(() {
                            _row = r;
                            _col = i;
                          });
                          _press();
                        }),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _keyView(_Key k, bool focused, VoidCallback onTap) {
    final fg = focused ? Tv.focusFg : Tv.text;
    final width = k.span * _cell + (k.span - 1) * _gapSize;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: 72,
        decoration: BoxDecoration(
          color: focused ? Tv.focusBg : (k.span > 1 ? const Color(0x0FFFFFFF) : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (k.icon != null) Icon(k.icon, size: 36, color: fg),
            if (k.icon != null && k.label.isNotEmpty) const SizedBox(width: 10),
            if (k.label.isNotEmpty)
              Text(
                k.label,
                style: TextStyle(fontSize: k.span > 1 ? 24 : 32, color: fg),
              ),
          ],
        ),
      ),
    );
  }
}
