import 'dart:async';

import 'package:flutter/material.dart';

import '../core/account.dart';
import '../core/library.dart';
import '../core/services.dart';
import '../innertube/innertube.dart';
import '../ui/actions.dart';
import '../ui/cards.dart';
import '../ui/overlay.dart';
import '../ui/theme.dart';
import 'playlist.dart';
import 'subscriptions.dart';

/// 媒體庫：保存在電視端的觀看紀錄、稍後觀看、喜歡的影片、已儲存播放清單與訂閱頻道。
/// 登入帳號後，也會一併顯示 YouTube 帳號的觀看紀錄、稍後觀看、喜歡的影片與播放清單。
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const _rowLimit = 20;

  /// 帳號清單：標題、項目列表，以及可檢視全部內容的播放清單（null 代表該列已顯示全部內容）。
  List<(String, List<YtItem>, PlaylistItem?)> _account = const [];
  Timer? _reload;

  @override
  void initState() {
    super.initState();
    Library.instance.addListener(_changed);
    Account.instance.addListener(_loadAccount);
    _loadAccount();
  }

  @override
  void dispose() {
    Library.instance.removeListener(_changed);
    Account.instance.removeListener(_loadAccount);
    _reload?.cancel();
    super.dispose();
  }

  /// 本機變更可能已同步至帳號（如稍後觀看、喜歡），延遲 3 秒後重新載入帳號清單。
  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (Account.instance.signedIn) {
      _reload?.cancel();
      _reload = Timer(const Duration(seconds: 3), _loadAccount);
    }
  }

  Future<void> _loadAccount() async {
    if (!Account.instance.signedIn) {
      if (mounted && _account.isNotEmpty) setState(() => _account = const []);
      return;
    }
    final yt = Services.yt;
    Future<List<YtItem>> safe(Future<List<YtItem>> f) => f.catchError((Object e) {
      debugPrint('YouPipe: account list failed: $e');
      return const <YtItem>[];
    });
    final lists = await Future.wait([
      safe(yt.accountFeed('FEhistory').then((p) => p.entries.allItems.whereType<VideoItem>().toList())),
      safe(yt.playlist('WL').then((p) => p.videos.items)),
      safe(yt.playlist('LL').then((p) => p.videos.items)),
      safe(yt.accountFeed('FEplaylist_aggregation').then((p) => p.entries.allItems.whereType<PlaylistItem>().toList())),
    ]);
    if (!mounted || !Account.instance.signedIn) return;
    setState(
      () => _account = [
        ('YouTube 觀看紀錄', lists[0], null),
        ('YouTube 稍後觀看', lists[1], const PlaylistItem(id: 'WL', title: '稍後觀看')),
        ('YouTube 喜歡的影片', lists[2], const PlaylistItem(id: 'LL', title: '喜歡的影片')),
        ('YouTube 播放清單', lists[3], null),
      ],
    );
  }

  /// 卡片操作選單，加上「從……移除」。
  ItemActions _actions(String key, String title) => defaultActions(
    context,
    extra: (item) => [
      PanelItem('從「$title」移除', icon: Icons.close, onSelect: () => Library.instance.remove(key, item.id)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final lib = Library.instance;
    final sections = <(String, List<YtItem>, String?)>[
      ('觀看紀錄', [for (final h in lib.history()) h.video], 'history'),
      for (final a in _account) (a.$1, a.$2, null),
      ('稍後觀看', lib.listOf('watchLater'), 'watchLater'),
      ('喜歡的影片', lib.listOf('liked'), 'liked'),
      ('已儲存的播放清單', lib.listOf('playlists'), 'playlists'),
      ('訂閱內容', lib.subscriptions(), null),
    ].where((s) => s.$2.isNotEmpty).toList();
    if (sections.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(Tv.pad, 152, Tv.pad, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('你的媒體庫目前是空的', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w500)),
            SizedBox(height: 16),
            Text(
              '你觀看過的影片、加入稍後觀看或喜歡的影片，以及儲存的播放清單都會顯示在這裡。',
              style: TextStyle(fontSize: 26, color: Tv.text2),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(Tv.pad, Tv.topbarHeight, 0, 600),
      children: [
        for (final s in sections)
          TvRow(
            key: ValueKey(s.$1),
            title: s.$1,
            items: s.$2.take(_rowLimit).toList(),
            actions: s.$3 == null ? defaultActions(context) : _actions(s.$3!, s.$1),
          ),
        // 項目超過上限時，可從下方開啟完整清單。
        if (sections.any((s) => s.$2.length > _rowLimit)) ...[
          const SizedBox(height: 8),
          for (final s in sections.where((s) => s.$2.length > _rowLimit))
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _SeeAll(
                title: s.$1,
                items: s.$2,
                actions: s.$3 == null ? null : _actions(s.$3!, s.$1),
                playlist: _account.where((a) => a.$1 == s.$1).firstOrNull?.$3,
              ),
            ),
        ],
      ],
    );
  }
}

class _SeeAll extends StatelessWidget {
  const _SeeAll({required this.title, required this.items, this.actions, this.playlist});

  final String title;
  final List<YtItem> items;
  final ItemActions? actions;

  /// 可完整分頁載入的帳號播放清單（如稍後觀看、喜歡的影片）。
  final PlaylistItem? playlist;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: PanelRow(
      item: PanelItem('查看全部：$title', value: playlist == null ? '${items.length}' : null, icon: Icons.grid_view),
      onSelect: () => Navigator.of(context).push(
        tvRoute(
          playlist != null
              ? PlaylistScreen(playlist: playlist!)
              : ListScreen(title: title, items: items, actions: actions),
        ),
      ),
    ),
  );
}
