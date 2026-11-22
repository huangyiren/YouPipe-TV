import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../core/extras.dart';
import '../core/format.dart';
import '../core/library.dart';
import '../core/services.dart';
import '../core/settings.dart';
import '../innertube/innertube.dart';
import '../player/captions.dart';
import '../player/video_info.dart';
import '../ui/actions.dart';
import '../ui/cards.dart';
import '../ui/focusable.dart';
import '../ui/overlay.dart';
import '../ui/shell.dart';
import '../ui/theme.dart';

/// The player screen, like YouTube on TV (docs/ui.md):
/// - The video fills the screen. OK, Up or Down shows the controls; Left/Right seek straight away with a preview.
/// - Controls: title and channel at the top; the seek bar (storyboard preview, chapters, SponsorBlock segments); a
///   row of buttons; and below it Up next (the queue, or related videos) as a grid, 3 across.
/// - Back hides the controls, then leaves the player.
class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key, required this.video, this.queue});

  final VideoItem video;
  final PlayQueue? queue;

  static _WatchScreenState? _current;

  /// Plays [video]; when the player is already open, it plays there.
  static void open(BuildContext context, VideoItem video, {PlayQueue? queue}) {
    final current = _current;
    if (current != null && current.mounted) {
      Navigator.of(context).popUntil((r) => r.settings.name == 'watch' || r.isFirst);
      current._play(video, queue: queue);
      return;
    }
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: 'watch'),
        transitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (context, a, b) => WatchScreen(video: video, queue: queue),
        transitionsBuilder: (context, a, b, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  static const _hideAfter = Duration(seconds: 5);
  final _player = Services.player;
  final _root = FocusNode(debugLabel: 'watch');
  final _bar = FocusNode(debugLabel: 'seekbar');
  final _playButton = FocusNode(debugLabel: 'play');
  final _upNext = FocusNode(debugLabel: 'upnext');

  late VideoItem _item;
  PlayQueue? _queue;
  List<YtItem> _related = const [];
  List<SbSegment> _segments = const [];
  final _skipped = <SbSegment>{};
  int? _dislikes;
  List<Cue>? _cues;
  CaptionTrack? _track;
  String _caption = '';

  bool _controls = true;
  bool _upNextFocused = false;
  final _column = GlobalKey();
  double _slide = 0;
  Duration? _scrubTo;
  int _scrubCount = 0;
  DateTime _lastScrub = DateTime(0);
  Timer? _hideTimer;
  Timer? _scrubTimer;
  Timer? _saveTimer;
  Timer? _countdownTimer;
  int? _countdown;
  VideoPlayerController? _listening;
  bool _completedHandled = false;

  @override
  void initState() {
    super.initState();
    WatchScreen._current = this;
    _player.controller.addListener(_onController);
    _player.info.addListener(_rebuild);
    _player.error.addListener(_onError);
    _upNext.addListener(() => setState(() => _upNextFocused = _upNext.hasFocus));
    _play(widget.video, queue: widget.queue);
  }

  @override
  void dispose() {
    if (WatchScreen._current == this) WatchScreen._current = null;
    _saveProgress();
    _hideTimer?.cancel();
    _scrubTimer?.cancel();
    _saveTimer?.cancel();
    _countdownTimer?.cancel();
    _listening?.removeListener(_onTick);
    _player.controller.removeListener(_onController);
    _player.info.removeListener(_rebuild);
    _player.error.removeListener(_onError);
    _player.stop();
    for (final n in [_root, _bar, _playButton, _upNext]) {
      n.dispose();
    }
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  VideoPlayerController? get _c => _player.controller.value;
  VideoInfo? get _info => _player.info.value;

  // Loading ------------------------------------------------------------------------------------------------------

  Future<void> _play(VideoItem video, {PlayQueue? queue}) async {
    _saveProgress();
    _countdownTimer?.cancel();
    setState(() {
      _item = video;
      _queue = queue;
      _related = const [];
      _segments = const [];
      _skipped.clear();
      _dislikes = null;
      _cues = null;
      _track = null;
      _caption = '';
      _countdown = null;
      _scrubTo = null;
      _completedHandled = false;
      // Up next leaves with its old cards; the controls drop back down for the new video.
      _upNextFocused = false;
      _slide = 0;
    });
    _showControls(focusPlay: true);
    Services.yt.related(video.id).then((p) {
      if (mounted && _item.id == video.id) {
        setState(() => _related = p.items.where((i) => i is! VideoItem || (!i.isShort && i.id != video.id)).toList());
      }
    }, onError: (Object e) => debugPrint('YouPipe: related failed: $e'));
    final h = Library.instance.progress(video.id);
    final resume = h != null && h.duration > 0 && h.position > 10 && h.position < h.duration - 30
        ? Duration(seconds: h.position)
        : Duration.zero;
    final ok = await _player.open(
      video.id,
      maxHeight: Settings.instance.maxHeight,
      start: resume,
      speed: Settings.instance.speed,
    );
    if (!ok || !mounted || _item.id != video.id) return;
    if (resume > Duration.zero) Toast.show('Resuming from ${formatDuration(resume)}');
    final info = _info;
    if (info != null) {
      _item = VideoItem(
        id: video.id,
        title: info.title.isNotEmpty ? info.title : video.title,
        channelName: info.channelName.isNotEmpty ? info.channelName : video.channelName,
        channelId: info.channelId ?? video.channelId,
        channelAvatar: info.channelAvatar ?? video.channelAvatar,
        thumbnail: video.thumbnail,
        durationText: video.durationText,
        viewsText: video.viewsText,
        publishedText: video.publishedText,
        isLive: info.isLive,
      );
      if (Settings.instance['captions'] == true) {
        final lang = Settings.instance.captionLang;
        final same = info.captions.where((t) => t.languageCode.split('-').first == lang).toList();
        final track =
            same.where((t) => !t.autoGenerated).firstOrNull ??
            same.firstOrNull ??
            info.captions.where((t) => !t.autoGenerated).firstOrNull;
        if (track != null) unawaited(_setCaptions(track));
      }
    }
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveProgress());
    SponsorBlock.segments(video.id).then((s) {
      if (mounted && _item.id == video.id) setState(() => _segments = s);
    });
    Dislikes.count(video.id).then((n) {
      if (mounted && _item.id == video.id) setState(() => _dislikes = n);
    });
  }

  void _onController() {
    _listening?.removeListener(_onTick);
    _listening = _c;
    _listening?.addListener(_onTick);
    _rebuild();
  }

  void _onError() {
    if (_player.error.value != null) _showControls(focusPlay: true);
    _rebuild();
  }

  void _saveProgress() {
    final c = _c;
    final info = _info;
    if (c == null || info == null || info.isLive || !c.value.isInitialized) return;
    final pos = c.value.position.inSeconds;
    if (pos < 3) return;
    Library.instance.saveProgress(_item, pos, c.value.duration.inSeconds);
  }

  // Playback events ----------------------------------------------------------------------------------------------

  void _onTick() {
    final c = _c;
    if (c == null || !mounted) return;
    final v = c.value;
    // SponsorBlock: skip each "skip" segment once.
    for (final s in _segments) {
      if (s.category.currentAction == 'skip' &&
          !_skipped.contains(s) &&
          v.position >= s.start &&
          v.position < s.end - const Duration(milliseconds: 500)) {
        _skipped.add(s);
        c.seekTo(s.end);
        Toast.show('Skipped ${s.category.label.toLowerCase()}');
        break;
      }
    }
    final cues = _cues;
    final caption = cues == null ? '' : Captions.at(cues, v.position);
    if (v.isCompleted && !_completedHandled) {
      _completedHandled = true;
      _onEnded();
    }
    if (caption != _caption || _controls) setState(() => _caption = caption);
  }

  void _onEnded() {
    _saveProgress();
    final next = _nextItem();
    if (next == null) return _showControls(focusPlay: true);
    if (_queue != null) {
      unawaited(_goNext());
      return;
    }
    if (!Settings.instance.autoplay) return _showControls(focusPlay: true);
    // YouTube's countdown before the next video.
    setState(() {
      _countdown = 5;
      _controls = false;
    });
    _root.requestFocus();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _countdown = _countdown! - 1);
      if (_countdown! <= 0) {
        t.cancel();
        _goNext();
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    setState(() => _countdown = null);
    _showControls(focusPlay: true);
  }

  // Queue ----------------------------------------------------------------------------------------------------------

  VideoItem? _nextItem() {
    final q = _queue;
    if (q != null) return q.index < q.items.length - 1 ? q.items[q.index + 1] : null;
    final watched = {for (final h in Library.instance.history().take(50)) h.video.id};
    final related = _related.whereType<VideoItem>();
    return related.where((v) => !watched.contains(v.id)).firstOrNull ?? related.firstOrNull;
  }

  Future<void> _goNext() async {
    final q = _queue;
    if (q != null && q.index >= q.items.length - 1 && q.more != null) {
      final more = await q.more!();
      q.items = [...q.items, ...more.where((m) => !q.items.any((i) => i.id == m.id))];
    }
    if (q != null && q.index < q.items.length - 1) {
      q.index++;
      return _play(q.items[q.index], queue: q);
    }
    final next = _nextItem();
    if (next != null) await _play(next);
  }

  void _goPrevious() {
    final c = _c;
    final q = _queue;
    if (c == null) return;
    if (c.value.position > const Duration(seconds: 5) || q == null || q.index == 0) {
      c.seekTo(Duration.zero);
      return;
    }
    q.index--;
    _play(q.items[q.index], queue: q);
  }

  // Controls ---------------------------------------------------------------------------------------------------------

  void _showControls({bool focusPlay = false, bool focusBar = false}) {
    if (!mounted) return;
    final wasHidden = !_controls;
    setState(() => _controls = true);
    if (focusBar) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bar.requestFocus());
    } else if (focusPlay || wasHidden) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _playButton.requestFocus());
    }
    _scheduleHide();
  }

  void _hideControls() {
    if (_scrubTo != null || _player.error.value != null) return;
    setState(() => _controls = false);
    _root.requestFocus();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideAfter, () {
      final c = _c;
      if (mounted && c != null && c.value.isPlaying && ModalRoute.of(context)?.isCurrent == true) _hideControls();
    });
  }

  void _togglePause() {
    final c = _c;
    if (c == null) return;
    c.value.isPlaying ? c.pause() : c.play();
    _showControls();
  }

  // Seeking ----------------------------------------------------------------------------------------------------------

  /// Moves the pending seek position; it's applied when the keys stop (or on OK).
  void _scrub(int dir) {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    if (_info?.isLive ?? false) {
      c.seekTo(c.value.position + Duration(seconds: 10 * dir));
      return;
    }
    final now = DateTime.now();
    _scrubCount = now.difference(_lastScrub) < const Duration(milliseconds: 500) ? _scrubCount + 1 : 0;
    _lastScrub = now;
    final step = Duration(seconds: _scrubCount > 20 ? 60 : (_scrubCount > 8 ? 30 : 10));
    final from = _scrubTo ?? c.value.position;
    final d = c.value.duration;
    var to = dir > 0 ? from + step : from - step;
    if (to < Duration.zero) to = Duration.zero;
    if (to > d - const Duration(seconds: 1)) to = d - const Duration(seconds: 1);
    setState(() => _scrubTo = to);
    _scrubTimer?.cancel();
    _scrubTimer = Timer(const Duration(milliseconds: 800), _commitScrub);
    _scheduleHide();
  }

  void _commitScrub() {
    final to = _scrubTo;
    _scrubTimer?.cancel();
    if (to == null) return;
    _c?.seekTo(to);
    setState(() => _scrubTo = null);
    _scheduleHide();
  }

  // Keys -------------------------------------------------------------------------------------------------------------

      _scheduleHide();
    if (k == LogicalKeyboardKey.arrowUp && _bar.hasFocus) {
      _hideControls();
      return KeyEventResult.handled;
    }
    // 確保在進度條按「下鍵」時，必定能跳到下方的播放與設定按鈕列
    if (k == LogicalKeyboardKey.arrowDown && _bar.hasFocus) {
      _playButton.requestFocus();
      return KeyEventResult.handled;
    }
    // 在按鈕列按「上鍵」時，若空間導航沒找到目標則回到進度條
    if (k == LogicalKeyboardKey.arrowUp && !_bar.hasFocus && !_upNextFocused) {
      if (FocusManager.instance.primaryFocus?.focusInDirection(TraversalDirection.up) != true) {
        _bar.requestFocus();
      }
      return KeyEventResult.handled;
    }
    final dir = TvKeys.direction(k);
    if (dir != null) {
      FocusManager.instance.primaryFocus?.focusInDirection(dir);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

