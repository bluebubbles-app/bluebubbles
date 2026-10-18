import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../models/conversation.dart';
import '../services/message_sounds.dart';
import '../theme/messages_theme.dart';

class MessageComposer extends StatefulWidget {
  const MessageComposer({
    super.key,
    required this.onSend,
    required this.onSendAttachment,
  });

  final ValueChanged<String> onSend;
  final void Function(MessageAttachment attachment, String caption)
      onSendAttachment;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  static const _channel = MethodChannel('bluebubbles/sms');
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _previewPlayer = AudioPlayer();
  bool _hasText = false;
  bool _busy = false;
  bool _recording = false;
  bool _previewPlaying = false;
  DateTime? _recordingStartedAt;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  MessageAttachment? _draftAttachment;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _previewPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _previewPlaying = false);
    });
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  void _send() {
    final text = _controller.text.trim();
    final attachment = _draftAttachment;
    if (text.isEmpty && attachment == null) return;
    HapticFeedback.lightImpact();
    unawaited(MessageSounds.playSent());
    if (attachment == null) {
      widget.onSend(text);
    } else {
      widget.onSendAttachment(attachment, text);
    }
    _controller.clear();
    setState(() => _draftAttachment = null);
    _focusNode.requestFocus();
  }

  Future<bool> _requestMediaPermission(String kind) async {
    final granted = await _channel.invokeMethod<bool>(
          'requestMediaPermission',
          {'kind': kind},
        ) ??
        false;
    if (!granted && mounted) {
      await _showError(
        kind == 'audio'
            ? 'Microphone Access Needed'
            : kind == 'camera'
                ? 'Camera Access Needed'
                : 'Photo Access Needed',
        'Allow access in Android settings to use this feature.',
      );
    }
    return granted;
  }

  Future<void> _startRecording() async {
    if (_busy || _recording || _hasText || _draftAttachment != null) return;
    setState(() => _busy = true);
    try {
      if (!await _requestMediaPermission('audio')) return;
      await _channel.invokeMethod<void>('startVoiceRecording');
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _recordingStartedAt = DateTime.now();
      _recordingDuration = Duration.zero;
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) {
          if (!mounted || _recordingStartedAt == null) return;
          setState(() {
            _recordingDuration = DateTime.now().difference(
              _recordingStartedAt!,
            );
          });
        },
      );
      setState(() => _recording = true);
    } on PlatformException catch (error) {
      if (mounted) {
        await _showError('Recording Failed', error.message ?? error.code);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording || _busy) return;
    setState(() => _busy = true);
    _recordingTimer?.cancel();
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'stopVoiceRecording',
      );
      if (!mounted || raw == null) return;
      final attachment = _attachmentFromNative(raw);
      setState(() {
        _recording = false;
        _recordingStartedAt = null;
        _recordingDuration = Duration(
          milliseconds: attachment.durationMilliseconds ??
              _recordingDuration.inMilliseconds,
        );
        _draftAttachment = attachment;
      });
      HapticFeedback.lightImpact();
    } on PlatformException catch (error) {
      if (mounted) {
        await _showError('Recording Failed', error.message ?? error.code);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    await _previewPlayer.stop();
    if (_recording) {
      await _channel.invokeMethod<void>('cancelVoiceRecording');
    } else {
      final attachment = _draftAttachment;
      final localPath = attachment?.localPath;
      if (attachment?.kind == MessageAttachmentKind.audio &&
          localPath != null) {
        try {
          await File(localPath).delete();
        } on FileSystemException {
          // The draft may already have been cleared by Android.
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _previewPlaying = false;
      _recordingStartedAt = null;
      _recordingDuration = Duration.zero;
      _draftAttachment = null;
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _togglePreviewPlayback() async {
    final attachment = _draftAttachment;
    final path = attachment?.localPath;
    if (attachment?.kind != MessageAttachmentKind.audio || path == null) {
      return;
    }
    if (_previewPlaying) {
      await _previewPlayer.pause();
      if (mounted) setState(() => _previewPlaying = false);
      return;
    }
    await _previewPlayer.play(DeviceFileSource(path));
    if (mounted) setState(() => _previewPlaying = true);
  }

  Future<void> _takePhoto() async {
    if (_busy || _recording) return;
    setState(() => _busy = true);
    try {
      if (!await _requestMediaPermission('camera')) return;
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'takePhoto',
      );
      if (!mounted || raw == null) return;
      setState(() => _draftAttachment = _attachmentFromNative(raw));
    } on PlatformException catch (error) {
      if (mounted) {
        await _showError('Camera Failed', error.message ?? error.code);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openMediaLibrary() async {
    if (_busy || _recording) return;
    setState(() => _busy = true);
    try {
      if (!await _requestMediaPermission('photos')) return;
      if (!mounted) return;
      final selected = await showCupertinoModalPopup<MessageAttachment>(
        context: context,
        builder: (context) => _MediaLibrarySheet(loadPage: _loadImagePage),
      );
      if (mounted && selected != null) {
        setState(() => _draftAttachment = selected);
      }
    } on PlatformException catch (error) {
      if (mounted) {
        await _showError(
          'Photos Could Not Be Loaded',
          error.message ?? error.code,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<MessageAttachment>> _loadImagePage(int offset) async {
    final raw = await _channel.invokeListMethod<Object?>(
      'loadRecentImages',
      {'limit': 24, 'offset': offset},
    );
    return (raw ?? const <Object?>[])
        .whereType<Map>()
        .map(
          (value) => _attachmentFromNative(
            Map<Object?, Object?>.from(value),
          ),
        )
        .where((value) => value.thumbnailBytes != null)
        .toList(growable: false);
  }

  MessageAttachment _attachmentFromNative(Map<Object?, Object?> raw) {
    final mimeType = (raw['mimeType'] ?? '').toString();
    return MessageAttachment(
      kind: mimeType.startsWith('audio/')
          ? MessageAttachmentKind.audio
          : MessageAttachmentKind.image,
      uri: (raw['uri'] ?? '').toString(),
      mimeType: mimeType,
      name: raw['name']?.toString(),
      localPath: raw['localPath']?.toString(),
      thumbnailBytes: raw['thumbnailBytes'] is Uint8List
          ? raw['thumbnailBytes'] as Uint8List
          : null,
      durationMilliseconds:
          (raw['durationMilliseconds'] as num?)?.toInt(),
    );
  }

  Future<void> _showError(String title, String message) =>
      showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );

  @override
  void dispose() {
    _recordingTimer?.cancel();
    if (_recording) {
      unawaited(_channel.invokeMethod<void>('cancelVoiceRecording'));
    }
    unawaited(_previewPlayer.dispose());
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final attachment = _draftAttachment;
    final isAudioDraft =
        attachment?.kind == MessageAttachmentKind.audio && !_recording;
    final canSend = _hasText || attachment != null;
    final isDark = MessagesPalette.isDark(context);

    return SafeArea(
      top: false,
      child: Container(
        color: MessagesPalette.background(context).withValues(alpha: .97),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (attachment?.kind == MessageAttachmentKind.image)
              _AttachmentPreview(
                attachment: attachment!,
                onRemove: _cancelRecording,
              ),
            SizedBox(
              height: 48,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (!_recording && !isAudioDraft) ...[
                    SizedBox(
                      width: 64,
                      child: CupertinoButton(
                        minSize: 48,
                        padding: EdgeInsets.zero,
                        onPressed: _busy ? null : _takePhoto,
                        child: Icon(
                          CupertinoIcons.camera_fill,
                          size: 31,
                          color: MessagesPalette.label(context)
                              .withValues(alpha: .45),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 59,
                      child: CupertinoButton(
                        minSize: 48,
                        padding: EdgeInsets.zero,
                        onPressed: _busy ? null : _openMediaLibrary,
                        child: Container(
                          width: 32,
                          height: 26,
                          decoration: BoxDecoration(
                            color: MessagesPalette.label(context)
                                .withValues(alpha: .45),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(
                            CupertinoIcons.photo_on_rectangle,
                            size: 17,
                            color: CupertinoColors.white,
                          ),
                        ),
                      ),
                    ),
                  ] else
                    const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 35,
                      decoration: BoxDecoration(
                        color: CupertinoColors.white.withValues(
                          alpha: isDark ? .08 : .5,
                        ),
                        border: Border.all(
                          color: MessagesPalette.hairline(context),
                          width: .7,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: _recording
                          ? _RecordingControls(
                              duration: _recordingDuration,
                              onCancel: _cancelRecording,
                              onStop: _stopRecording,
                              busy: _busy,
                            )
                          : isAudioDraft
                              ? _AudioDraftControls(
                                  duration: Duration(
                                    milliseconds:
                                        attachment!.durationMilliseconds ?? 0,
                                  ),
                                  playing: _previewPlaying,
                                  onPlayPause: _togglePreviewPlayback,
                                  onCancel: _cancelRecording,
                                  onSend: _send,
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: CupertinoTextField(
                                        controller: _controller,
                                        focusNode: _focusNode,
                                        placeholder: 'iMessage',
                                        placeholderStyle: const TextStyle(
                                          fontFamily: 'SF Pro Text',
                                          color: Color(0x4D3C3C43),
                                          fontSize: 17,
                                          height: 1.2,
                                        ),
                                        style: MessagesText.body(context),
                                        minLines: 1,
                                        maxLines: 1,
                                        textCapitalization:
                                            TextCapitalization.sentences,
                                        keyboardType: TextInputType.multiline,
                                        decoration: null,
                                        padding: const EdgeInsets.fromLTRB(
                                          13,
                                          6,
                                          4,
                                          7,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 34,
                                      height: 34,
                                      child: AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 140),
                                        child: GestureDetector(
                                          key: const ValueKey(
                                            'voice-message-button',
                                          ),
                                          onLongPress: canSend || _busy
                                              ? null
                                              : _startRecording,
                                          child: CupertinoButton(
                                            key: ValueKey(canSend),
                                            minSize: 34,
                                            padding: EdgeInsets.zero,
                                            onPressed: canSend
                                                ? _send
                                                : (_busy
                                                    ? null
                                                    : _startRecording),
                                            child: canSend
                                                ? const Icon(
                                                    CupertinoIcons
                                                        .arrow_up_circle_fill,
                                                    size: 30,
                                                    color:
                                                        MessagesPalette.blue,
                                                  )
                                                : _VoiceWaveIcon(
                                                    color:
                                                        MessagesPalette.label(
                                                      context,
                                                    ).withValues(alpha: .45),
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                  ],
                                ),
                    ),
                  ),
                  if (!_recording && !isAudioDraft)
                    const SizedBox(width: 16)
                  else
                    const SizedBox(width: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceWaveIcon extends StatelessWidget {
  const _VoiceWaveIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 27,
        height: 27,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final height in const [4.0, 10.0, 15.0, 11.0, 7.0, 4.0])
              Container(
                width: 2,
                height: height,
                margin: const EdgeInsets.symmetric(horizontal: .7),
                decoration: BoxDecoration(
                  color: CupertinoColors.white,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
          ],
        ),
      );
}

class _RecordingControls extends StatelessWidget {
  const _RecordingControls({
    required this.duration,
    required this.onCancel,
    required this.onStop,
    required this.busy,
  });

  final Duration duration;
  final VoidCallback onCancel;
  final VoidCallback onStop;
  final bool busy;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          CupertinoButton(
            minSize: 33,
            padding: const EdgeInsets.only(left: 8, right: 5),
            onPressed: busy ? null : onCancel,
            child: const Icon(
              CupertinoIcons.xmark_circle_fill,
              size: 22,
              color: CupertinoColors.systemGrey,
            ),
          ),
          const _RecordingDot(),
          const SizedBox(width: 7),
          Text(
            '${duration.inMinutes}:${duration.inSeconds.remainder(60).toString().padLeft(2, '0')}',
            style: TextStyle(
              fontFamily: 'SF Pro Text',
              fontSize: 15,
              color: MessagesPalette.label(context),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(child: _WaveformBars(active: true)),
          CupertinoButton(
            minSize: 33,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            onPressed: busy ? null : onStop,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: CupertinoColors.systemRed,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: CupertinoColors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      );
}

class _RecordingDot extends StatefulWidget {
  const _RecordingDot();

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
    lowerBound: .35,
    upperBound: 1,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _controller,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            color: CupertinoColors.systemRed,
            shape: BoxShape.circle,
          ),
          child: SizedBox(width: 8, height: 8),
        ),
      );
}

class _AudioDraftControls extends StatelessWidget {
  const _AudioDraftControls({
    required this.duration,
    required this.playing,
    required this.onPlayPause,
    required this.onCancel,
    required this.onSend,
  });

  final Duration duration;
  final bool playing;
  final VoidCallback onPlayPause;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          CupertinoButton(
            minSize: 32,
            padding: const EdgeInsets.only(left: 7, right: 2),
            onPressed: onCancel,
            child: const Icon(
              CupertinoIcons.xmark_circle_fill,
              size: 22,
              color: CupertinoColors.systemGrey,
            ),
          ),
          CupertinoButton(
            minSize: 30,
            padding: EdgeInsets.zero,
            onPressed: onPlayPause,
            child: Icon(
              playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
              size: 18,
              color: MessagesPalette.blue,
            ),
          ),
          const SizedBox(width: 4),
          const Expanded(child: _WaveformBars(active: false)),
          const SizedBox(width: 6),
          Text(
            '${duration.inMinutes}:${duration.inSeconds.remainder(60).toString().padLeft(2, '0')}',
            style: TextStyle(
              fontFamily: 'SF Pro Text',
              fontSize: 12,
              color: MessagesPalette.secondaryLabel(context),
            ),
          ),
          CupertinoButton(
            minSize: 33,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            onPressed: onSend,
            child: const Icon(
              CupertinoIcons.arrow_up_circle_fill,
              size: 30,
              color: MessagesPalette.blue,
            ),
          ),
        ],
      );
}

class _WaveformBars extends StatelessWidget {
  const _WaveformBars({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var index = 0; index < 18; index++)
            Container(
              width: 2,
              height: const [5.0, 11.0, 17.0, 8.0, 14.0, 6.0, 16.0, 10.0]
                  [index % 8],
              decoration: BoxDecoration(
                color: (active
                        ? CupertinoColors.systemRed
                        : MessagesPalette.blue)
                    .withValues(alpha: index.isEven ? .85 : .5),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      );
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({
    required this.attachment,
    required this.onRemove,
  });

  final MessageAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 16, 2),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: attachment.thumbnailBytes == null
                    ? Container(
                        width: 72,
                        height: 72,
                        color: CupertinoColors.systemGrey5,
                        child: const Icon(CupertinoIcons.photo),
                      )
                    : Image.memory(
                        attachment.thumbnailBytes!,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
              ),
              Positioned(
                right: -9,
                top: -9,
                child: CupertinoButton(
                  minSize: 26,
                  padding: EdgeInsets.zero,
                  onPressed: onRemove,
                  child: const Icon(
                    CupertinoIcons.xmark_circle_fill,
                    size: 24,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _MediaLibrarySheet extends StatefulWidget {
  const _MediaLibrarySheet({required this.loadPage});

  final Future<List<MessageAttachment>> Function(int offset) loadPage;

  @override
  State<_MediaLibrarySheet> createState() => _MediaLibrarySheetState();
}

class _MediaLibrarySheetState extends State<_MediaLibrarySheet> {
  static const _pageSize = 24;
  final _images = <MessageAttachment>[];
  final _scrollController = ScrollController();
  double _height = 296;
  bool _loading = false;
  bool _hasMore = true;
  int _nextOffset = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_loadNextPage());
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 500) {
      unawaited(_loadNextPage());
    }
  }

  Future<void> _loadNextPage() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.loadPage(_nextOffset);
      if (!mounted) return;
      setState(() {
        _images.addAll(page);
        _nextOffset += _pageSize;
        // A final empty page is cheaper than stopping early when MediaStore
        // contains an unreadable or unsupported thumbnail in the current page.
        _hasMore = page.isNotEmpty;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  Widget _buildGallery(BuildContext context) {
    if (_images.isEmpty && _loading) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (_images.isEmpty && _error != null) {
      return Center(
        child: CupertinoButton(
          onPressed: _loadNextPage,
          child: const Text('Try Again'),
        ),
      );
    }
    if (_images.isEmpty) {
      return Center(
        child: Text(
          'No photos available',
          style: MessagesText.secondary(context),
        ),
      );
    }
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 122 / 117,
      ),
      itemCount: _images.length + (_loading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _images.length) {
          return const Center(
            child: CupertinoActivityIndicator(radius: 10),
          );
        }
        final image = _images[index];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.pop(context, image),
          child: Image.memory(
            image.thumbnailBytes!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            cacheWidth: 360,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final maximumHeight = MediaQuery.sizeOf(context).height -
        MediaQuery.paddingOf(context).top -
        8;
    final minimumHeight = maximumHeight < 296 ? maximumHeight : 296.0;
    return Container(
      height: _height.clamp(minimumHeight, maximumHeight),
      decoration: BoxDecoration(
        color: MessagesPalette.background(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
      ),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (details) {
              setState(() {
                _height = (_height - details.delta.dy).clamp(
                  minimumHeight,
                  maximumHeight,
                );
              });
            },
            onVerticalDragEnd: (_) {
              setState(() {
                _height = _height > (minimumHeight + maximumHeight) / 2
                    ? maximumHeight
                    : minimumHeight;
              });
            },
            child: SizedBox(
              height: 54,
              child: Stack(
                children: [
                  Align(
                    alignment: const Alignment(0, -.8),
                    child: Container(
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFBEBEC0),
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    top: 15,
                    child: CupertinoButton(
                      minSize: 30,
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.pop(context),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEEEEEF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.xmark,
                          size: 17,
                          color: Color(0xFF838388),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: _buildGallery(context)),
        ],
      ),
    );
  }
}
