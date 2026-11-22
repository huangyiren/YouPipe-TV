import 'package:flutter/material.dart';

import '../core/account.dart';
import '../ui/cards.dart';
import '../ui/focusable.dart';
import '../ui/overlay.dart';
import '../ui/shell.dart';
import '../ui/theme.dart';

/// 帳戶頁面：從左側選單頂端開啟。未登入時提供 Google 登入頁面；
/// 登入後顯示使用者資訊、匯入訂閱頻道與觀看紀錄，以及登出選項。
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  String? _imported;

  @override
  void initState() {
    super.initState();
    Account.instance.addListener(_changed);
  }

  @override
  void dispose() {
    Account.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// 登入或登出後按鈕會切換，將焦點重新移回畫面上的新按鈕。
  void _refocus() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) context.findAncestorStateOfType<ShellState>()?.focusScreen();
  });

  Future<void> _signIn() async {
    final bool ok;
    try {
      ok = await Account.instance.signIn();
    } catch (e) {
      Toast.show('無法開啟 Google 登入頁面');
      debugPrint('YouPipe: sign-in failed: $e');
      return;
    }
    if (!ok) return;
    _refocus();
    final name = Account.instance.info?.name;
    Toast.show(name == null ? '已登入' : '已登入為 $name');
    await _import();
  }

  Future<void> _import() async {
    if (Account.instance.importing) return;
    Toast.show('正在從你的帳號匯入資料…');
    try {
      final (subs, videos) = await Account.instance.import();
      _imported = '已新增 $subs 個訂閱頻道、$videos 部觀看紀錄影片';
      Toast.show('已匯入 $subs 個訂閱頻道與 $videos 部觀看紀錄影片');
    } catch (e) {
      debugPrint('YouPipe: account import failed: $e');
      Toast.show('無法從你的帳號匯入資料');
    }
    if (mounted) setState(() {});
  }

  void _signOut() => showConfirm(context, '確定要登出嗎？', '登出', () async {
    await Account.instance.signOut();
    _imported = null;
    _refocus();
    Toast.show('已登出');
  }, detail: '保存在這台電視上的媒體庫資料仍會保留。');

  @override
  Widget build(BuildContext context) {
    final a = Account.instance;
    if (!a.signedIn) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Tv.pad, 120, Tv.pad, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('登入 YouTube', style: Tv.pageTitle),
            const SizedBox(height: 28),
            const SizedBox(
              width: 1180,
              child: Text(
                '將你的 YouTube 帳號帶入 YouPipe：在首頁檢視個人化推薦內容、同步訂閱頻道與觀看紀錄，'
                '並在媒體庫中存取你的播放清單、稍後觀看與喜歡的影片。按讚、訂閱與稍後觀看也會同步回你的帳號。',
                style: TextStyle(fontSize: 28, height: 1.4, color: Tv.text),
              ),
            ),
            const SizedBox(height: 20),
            const SizedBox(
              width: 1180,
              child: Text(
                '接下來將開啟 Google 官方登入頁面。你可以用電視遙控器輸入電子郵件與密碼，'
                '或使用手機上的 Google TV 應用程式鍵盤輸入。登入狀態僅保存在這台電視上。',
                style: TextStyle(fontSize: 24, height: 1.4, color: Tv.text2),
              ),
            ),
            const SizedBox(height: 48),
            TvButton(label: '登入', icon: Icons.login, primary: true, onSelect: _signIn),
          ],
        ),
      );
    }
    final info = a.info;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Tv.pad, 120, Tv.pad, 400),
      children: [
        Row(
          children: [
            ClipOval(child: NetImage(info?.photo, width: 128, height: 128)),
            const SizedBox(width: 36),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(info?.name ?? '已登入', style: Tv.pageTitle),
                  if ((info?.handle ?? info?.email) != null) ...[
                    const SizedBox(height: 8),
                    Text(info!.handle ?? info.email!, style: const TextStyle(fontSize: 26, color: Tv.text2)),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 56),
        for (final item in [
          PanelItem(
            '匯入訂閱頻道與觀看紀錄',
            sub: a.importing ? '正在匯入…' : (_imported ?? '將帳號中的訂閱與紀錄複製到此電視'),
            icon: Icons.download,
            onSelect: _import,
          ),
          PanelItem('登出', sub: '保存在這台電視上的媒體庫資料仍會保留', icon: Icons.logout, onSelect: _signOut),
        ])
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(width: 1120, child: PanelRow(item: item)),
          ),
      ],
    );
  }
}
