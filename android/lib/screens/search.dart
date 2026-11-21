import 'dart:async';

import 'package:flutter/material.dart';

import '../core/library.dart';
import '../core/services.dart';
import '../innertube/innertube.dart';
import '../ui/actions.dart';
import '../ui/cards.dart';
import '../ui/focusable.dart';
import '../ui/keyboard.dart';
import '../ui/theme.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _inputFocus = FocusNode();
  final _keyboard = FocusNode();
  final _results = FocusNode();
  String _text = '';
  List<String> _suggestions = const [];
  bool _showingResults = false;
  bool _isRecent = true;
  String _heading = '';
  List<YtItem> _items = const [];
  String? _token;
  bool _loadingMore = false;
  Timer? _debounce;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _onChanged('');
    WidgetsBinding.instance.addPostFrameCallback((_) => _inputFocus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _inputFocus.dispose();
    _keyboard.dispose();
    _results.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final seq = ++_seq;
    setState(() {
      _text = text;
      _showingResults = false;
      if (text.trim().isEmpty) {
        _isRecent = true;
        _heading = '近期搜尋';
        _suggestions = Library.instance.searches();
      }
    });
    if (text.trim().isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final list = await Services.yt.suggestions(text);
        if (mounted && seq == _seq) {
          setState(() {
            _isRecent = false;
            _heading = '搜尋建議';
            _suggestions = list.take(10).toList();
          });
        }
      } catch (e) {
        debugPrint('YouPipe: suggestions failed: $e');
      }
    });
  }

  Future<void> _run(String query) async {
    query = query.trim();
    if (query.isEmpty) return;
    _debounce?.cancel();
    final seq = ++_seq;
    Library.instance.addSearch(query);
    final fromSuggestions = !_keyboard.hasFocus && !_inputFocus.hasFocus;
    setState(() {
      _text = query;
      _showingResults = true;
      _heading = '正在搜尋「$query」…';
      _items = const [];
    });
    try {
      final page = await Services.yt.search(query);
      if (!mounted || seq != _seq) return;
      final items = page.entries.allItems.where((i) => i is! VideoItem || !i.isShort).toList();
      setState(() {
        _items = items;
        _token = page.continuation;
        _heading = items.isEmpty ? '找不到「$query」的相關結果' : '「$query」的搜尋結果';
      });
      if (fromSuggestions && items.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _results.requestFocus());
      }
    } catch (e) {
      if (mounted) setState(() => _heading = '搜尋失敗：$e');
    }
  }

  Future<void> _more() async {
    final t = _token;
    if (t == null || _loadingMore) return;
    _loadingMore = true;
    try {
      final p = await Services.yt.searchContinuation(t);
      if (!mounted) return;
      final seen = _items.map((i) => i.id).toSet();
      setState(() {
        _token = p.continuation;
        _items = [..._items, ...p.entries.allItems.where((i) => (i is! VideoItem || !i.isShort) && seen.add(i.id))];
      });
    } finally {
      _loadingMore = false;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_results.hasFocus,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _inputFocus.requestFocus();
    },
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Tv.pad, 72, 0, 0),
          child: TvKeyboard(
            text: _text,
            focusNode: _keyboard,
            inputFocusNode: _inputFocus,
            onChanged: _onChanged,
            onSubmit: _run,
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(48, 72, Tv.pad, 72),
            children: [
              Text(_heading, style: const TextStyle(fontSize: 26, color: Tv.text2)),
              const SizedBox(height: 18),
              if (_showingResults)
                TvGrid(
                  items: _items,
                  columns: 3,
                  cardWidth: 330,
                  focusNode: _results,
                  actions: defaultActions(context),
                  onNearEnd: _more,
                )
              else
                for (final s in _suggestions)
                  TvFocusable(
                    onSelect: () => _run(s),
                    builder: (context, focused) => Container(
                      height: 76,
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      decoration: BoxDecoration(
                        color: focused ? Tv.focusBg : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isRecent ? Icons.history : Icons.search,
                            size: 32,
                            color: focused ? Tv.focusFg : Tv.text2,
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Text(
                              s,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 30, color: focused ? Tv.focusFg : const Color(0xFFDDDDDD)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ],
    ),
  );
}
