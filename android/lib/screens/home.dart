import 'package:flutter/material.dart';

import '../core/account.dart';
import '../core/home_rows.dart';
import '../core/library.dart';
import '../innertube/innertube.dart';
import '../ui/actions.dart';
import '../ui/cards.dart';
import '../ui/focusable.dart';
import '../ui/shell.dart';
import '../ui/theme.dart';

class _Row {
  _Row(this.source);

  final RowSource source;
  List<YtItem> items = const [];
  bool loading = true;
  bool exhausted = false;
  bool fetchingMore = false;
  final focus = FocusNode();
}

/// 首頁：橫向滑動的影片推薦列（資料來源定義於 core/home_rows.dart）。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<_Row> _rows = [];
  DateTime _builtAt = DateTime.now();
  bool _failed = false;

  static const _titleMap = <String, String>{
    'Continue watching': '繼續觀看',
    'Recommended': '為你推薦',
    'Subscriptions': '訂閱內容',
    'Trending': '發燒影片',
    'Music': '音樂',
    'Gaming': '遊戲',
    'News': '新聞',
    'Sports': '體育',
  };

  String _localizeTitle(String title) => _titleMap[title] ?? title;

  @override
  void initState() {
    super.initState();
    Library.instance.addListener(_onLibrary);
    Account.instance.addListener(_onAccount);
    _build();
  }

  @override
  void dispose() {
    Library.instance.removeListener(_onLibrary);
    Account.instance.removeListener(_onAccount);
    for (final r in _rows) {
      r.focus.dispose();
    }
    super.dispose();
  }

  /// 觀看影片後，「繼續觀看」列會更新播放進度（除非焦點正停留在該列）。若首頁建立超過一小時則重新整理。
  void _onLibrary() {
    if (!mounted) return;
    if (DateTime.now().difference(_builtAt) > const Duration(hours: 1)) return _build();
    final row = _rows.where((r) => r.source.title == 'Continue watching').firstOrNull;
    if (row == null || row.focus.hasFocus) return;
    setState(() => row.items = [for (final h in Library.instance.continueWatching().take(30)) h.video]);
  }

  /// 登入或登出後，重新載入首頁推薦內容。
  bool _signedIn = Account.instance.signedIn;

  void _onAccount() {
    if (!mounted || _signedIn == Account.instance.signedIn) return;
    _signedIn = Account.instance.signedIn;
    _build();
  }

  void _build() {
    _builtAt = DateTime.now();
    _keysAtBuild = KeyCounter.count;
    _failed = false;
    final rows = [for (final s in HomeRows.sources()) _Row(s)];
    setState(() => _rows = rows);
    runQueued([
      for (final r in rows)
        () async {
          try {
            final items = await r.source.load();
            if (!mounted) return;
            setState(() {
              r.items = items;
              r.loading = false;
            });
          } catch (e) {
            debugPrint('YouPipe: home row "${r.source.title}" failed: $e');
            if (mounted) setState(() => r.loading = false);
          }
          _focusTopRow();
        },
    ]).then((_) {
      if (mounted && _rows.every((r) => r.items.isEmpty)) setState(() => _failed = true);
      Splash.done();
    });
  }

  /// 待上方所有列載入完成或失敗後，將遙控器焦點自動移至最頂端有內容的列，避免焦點跳動。
  void _focusTopRow() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    for (final r in _rows) {
      if (r.loading) return;
      if (r.items.isEmpty) continue;
      Splash.done();
      final idle = KeyCounter.count == _keysAtBuild && !_rows.any((x) => x.focus.hasFocus);
      final shown = TickerMode.valuesOf(context).enabled && ModalRoute.of(context)?.isCurrent != false;
      if (idle && shown) r.focus.requestFocus();
      return;
    }
  });

  int _keysAtBuild = 0;

  Future<void> _more(_Row r) async {
    final more = r.source.more;
    if (more == null || r.exhausted || r.fetchingMore) return;
    r.fetchingMore = true;
    try {
      final items = await more();
      if (!mounted) return;
      final seen = r.items.map((i) => i.id).toSet();
      setState(() {
        if (items.isEmpty) r.exhausted = true;
        r.items = [...r.items, ...items.where((i) => seen.add(i.id))];
      });
    } catch (e) {
      r.exhausted = true;
    } finally {
      r.fetchingMore = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('無法載入首頁', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            const Text('請確認電視已連線至網路後再試一次。', style: TextStyle(fontSize: 26, color: Tv.text2)),
            const SizedBox(height: 36),
            TvButton(label: '重試', autofocus: true, onSelect: _build),
          ],
        ),
      );
    }
    final visible = _rows.where((r) => r.loading || r.items.isNotEmpty).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(Tv.pad, Tv.topbarHeight, 0, 600),
      children: [
        for (final r in visible)
          TvRow(
            key: ObjectKey(r),
            title: _localizeTitle(r.source.title),
            items: r.items,
            loading: r.loading,
            focusNode: r.focus,
            actions: defaultActions(context),
            onNearEnd: () => _more(r),
          ),
      ],
    );
  }
}
