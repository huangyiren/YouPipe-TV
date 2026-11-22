import 'package:flutter/material.dart';

import '../core/extras.dart';
import '../core/library.dart';
import '../core/settings.dart';
import '../core/updates.dart';
import '../ui/overlay.dart';
import '../ui/theme.dart';
import '../ui/updates.dart';

/// 設定頁面：採用側邊面板展開選項，與電視版 YouTube 操作體驗一致。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _qualities = <(Object, String)>[
    ('auto', '自動（最高 1080p）'),
    (1080, '1080p'),
    (720, '720p'),
    (480, '480p'),
    (360, '360p'),
  ];
  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  static const _regions = <(String, String)>[
    ('TW', '台灣'),
    ('HK', '香港'),
    ('SG', '新加坡'),
    ('JP', '日本'),
    ('KR', '南韓'),
    ('US', '美國'),
    ('GB', '英國'),
    ('IE', '愛爾蘭'),
    ('IN', '印度'),
    ('CA', '加拿大'),
    ('AU', '澳洲'),
    ('DE', '德國'),
    ('FR', '法國'),
    ('ES', '西班牙'),
    ('IT', '義大利'),
    ('NL', '荷蘭'),
    ('BR', '巴西'),
    ('MX', '墨西哥'),
    ('AE', '阿拉伯聯合大公國'),
  ];
  static const _languages = <(String?, String)>[
    ('zh-TW', '繁體中文'),
    ('zh-CN', '簡體中文'),
    (null, '與電視系統相同'),
    ('en', 'English（英文）'),
    ('ja', '日本語（日文）'),
    ('ko', '한국어（韓文）'),
    ('de', 'Deutsch'),
    ('es', 'Español'),
    ('fr', 'Français'),
    ('hi', 'हिन्दी'),
    ('it', 'Italiano'),
    ('ml', 'മലയാളം'),
    ('nl', 'Nederlands'),
    ('pt', 'Português'),
    ('ta', 'தமிழ்'),
  ];

  @override
  void initState() {
    super.initState();
    Settings.instance.addListener(_changed);
    Library.instance.addListener(_changed);
    Updates.available.addListener(_changed);
  }

  @override
  void dispose() {
    Settings.instance.removeListener(_changed);
    Library.instance.removeListener(_changed);
    Updates.available.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String _label<T>(List<(T, String)> pairs, T value) => pairs.where((p) => p.$1 == value).firstOrNull?.$2 ?? '$value';

  void _choose<T>(String title, List<(T, String)> pairs, T value, void Function(T) apply) => showPanel(
    context,
    title: title,
    items: [for (final p in pairs) PanelItem(p.$2, checked: p.$1 == value, onSelect: () => apply(p.$1))],
  );

  void _sponsorBlockCategories() {
    final actions = Settings.instance.sbActions;
    showPanel(
      context,
      title: 'SponsorBlock 片段分類',
      subtitle: '設定遇到各類廣告／贊助片段時的處理方式',
      items: [
        for (final c in SbCategory.all)
          PanelItem(
            c.label,
            color: c.color,
            value: const {'skip': '自動跳過', 'show': '在進度條標示', 'off': '關閉'}[actions[c.key] ?? c.action],
            onSelect: () => _choose<String>(
              c.label,
              const [('skip', '自動跳過'), ('show', '在進度條標示'), ('off', '關閉')],
              actions[c.key] ?? c.action,
              (a) => Settings.instance.set('sbActions', {...Settings.instance.sbActions, c.key: a}),
            ),
          ),
      ],
    );
  }

  Future<void> _checkUpdates() async {
    Toast.show('正在檢查更新…');
    try {
      final latest = await Updates.check(force: true);
      if (!mounted) return;
      if (Updates.isNewer(latest, Updates.version)) {
        offerUpdate(context, latest);
      } else {
        Toast.show('YouPipe 已是最新版本（${Updates.version}）');
      }
    } catch (e) {
      Toast.show('無法檢查更新：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Settings.instance;
    final lib = Library.instance;
    String onOff(bool v) => v ? '開啟' : '關閉';
    final rows = <Object>[
      '播放設定',
      PanelItem(
        '影片畫質',
        value: _label<Object>(_qualities, s['quality'] ?? 'auto'),
        onSelect: () => _choose<Object>('影片畫質', _qualities, s['quality'] ?? 'auto', (v) => s.set('quality', v)),
      ),
      PanelItem('自動播放下一部影片', value: onOff(s.autoplay), onSelect: () => s.set('autoplay', !s.autoplay)),
      PanelItem(
        '預設開啟字幕',
        value: onOff(s['captions'] == true),
        onSelect: () => s.set('captions', s['captions'] != true),
      ),
      PanelItem(
        '字幕語言',
        value: _label<String?>(_languages, s['captionLang'] as String?),
        onSelect: () =>
            _choose<String?>('字幕語言', _languages, s['captionLang'] as String?, (v) => s.set('captionLang', v)),
      ),
      PanelItem(
        '播放速度',
        value: s.speed == 1 ? '正常' : '${s.speed}×',
        onSelect: () => _choose<double>(
          '播放速度',
          [for (final v in _speeds) (v, v == 1 ? '正常' : '$v×')],
          s.speed,
          (v) => s.set('speed', v),
        ),
      ),
      '擴充功能',
      PanelItem(
        'SponsorBlock：跳過贊助與業配片段',
        sub: '使用 sponsor.ajay.app 社群標記資料',
        value: onOff(s.sponsorBlock),
        onSelect: () => s.set('sponsorBlock', !s.sponsorBlock),
      ),
      if (s.sponsorBlock) PanelItem('片段分類設定', onSelect: _sponsorBlockCategories),
      PanelItem(
        'Return YouTube Dislike（顯示倒讚數）',
        sub: '顯示來自 returnyoutubedislike.com 的預估倒讚數量',
        value: onOff(s.dislikes),
        onSelect: () => s.set('dislikes', !s.dislikes),
      ),
      '內容與地區',
      PanelItem(
        '地區',
        sub: 'YouTube 推薦影片所依據的國家／地區',
        value: _label<String>(_regions, s.gl),
        onSelect: () => _choose<String>('地區', _regions, s.gl, (v) => s.set('gl', v)),
      ),
      PanelItem(
        '內容語言',
        sub: 'YouTube 影片標題與時間顯示的語言',
        value: _label<String?>(_languages, s['hl'] as String?),
        onSelect: () => _choose<String?>('內容語言', _languages, s['hl'] as String?, (v) => s.set('hl', v)),
      ),
      '隱私權',
      PanelItem(
        '清除觀看紀錄',
        value: '${lib.history().length} 部影片',
        onSelect: () => showConfirm(context, '確定要清除觀看紀錄嗎？', '清除', () => lib.clear('history')),
      ),
      PanelItem(
        '清除搜尋紀錄',
        value: '${lib.searches().length} 筆搜尋',
        onSelect: () => showConfirm(context, '確定要清除搜尋紀錄嗎？', '清除', () => lib.clear('searches')),
      ),
      '關於',
      PanelItem(
        '版本',
        sub: Updates.available.value == null ? '點選檢查更新' : '有新版本 ${Updates.available.value} 可供更新',
        value: Updates.version,
        onSelect: _checkUpdates,
      ),
      PanelItem('原始碼倉庫', value: '://github.com{Updates.repo}'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(Tv.pad, 120, Tv.pad, 400),
      children: [
        const Text('設定', style: Tv.pageTitle),
        const SizedBox(height: 32),
        for (final r in rows)
          if (r is String)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 36, 0, 10),
              child: Text(
                r,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: Tv.text2),
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(width: 1120, child: PanelRow(item: r as PanelItem)),
            ),
      ],
    );
  }
}
