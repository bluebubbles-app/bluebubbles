import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../models/conversation.dart';
import '../services/message_sounds.dart';
import '../settings/app_settings.dart';
import '../theme/messages_theme.dart';
import 'liquid_glass_surface.dart';

class MessageComposer extends StatefulWidget {
  const MessageComposer({
    super.key,
    required this.onSend,
    required this.onSendAttachment,
    this.compactLeadingAction = false,
    this.enabled = true,
    this.focusNode,
  });

  final ValueChanged<String> onSend;
  final void Function(MessageAttachment attachment, String caption)
      onSendAttachment;
  final bool compactLeadingAction;
  final bool enabled;
  final FocusNode? focusNode;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  static const _channel = MethodChannel('bluebubbles/sms');
  final _controller = TextEditingController();
  late final FocusNode _focusNode;
  late final bool _ownsFocusNode;
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
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
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
    if (!widget.enabled) return;
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
    if (!widget.enabled ||
        _busy ||
        _recording ||
        _hasText ||
        _draftAttachment != null) {
      return;
    }
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
      final useIos26 =
          AppSettingsScope.maybeOf(context)?.interfaceStyle ==
              InterfaceStyle.ios26;
      final selected = await showCupertinoModalPopup<MessageAttachment>(
        context: context,
        barrierColor: useIos26
            ? CupertinoColors.transparent
            : const Color(0x33000000),
        builder: (context) => _MediaLibrarySheet(
          loadPage: _loadImagePage,
          pickFromGallery: _pickGalleryImage,
          useIos26: useIos26,
        ),
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

  Future<void> _showCompactAttachmentMenu() async {
    if (_busy || _recording) return;
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'camera'),
            child: const Text('Camera'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'photos'),
            child: const Text('Photo Library'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'camera') {
      await _takePhoto();
    } else if (action == 'photos') {
      await _openMediaLibrary();
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

  Future<MessageAttachment?> _pickGalleryImage() async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'pickGalleryImage',
    );
    if (raw == null) return null;
    return _attachmentFromNative(raw);
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
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final attachment = _draftAttachment;
    final isAudioDraft =
        attachment?.kind == MessageAttachmentKind.audio && !_recording;
    final canSend = widget.enabled && (_hasText || attachment != null);
    final isDark = MessagesPalette.isDark(context);
    final settings = AppSettingsScope.maybeOf(context);

    if (settings?.interfaceStyle == InterfaceStyle.ios3) {
      return _buildIos3Composer(
        context,
        attachment: attachment,
        isAudioDraft: isAudioDraft,
        canSend: canSend,
      );
    }

    if (settings?.interfaceStyle == InterfaceStyle.ios26) {
      return _buildIos26Composer(
        context,
        settings!,
        attachment: attachment,
        isAudioDraft: isAudioDraft,
        canSend: canSend,
      );
    }

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
                    if (widget.compactLeadingAction)
                      SizedBox(
                        width: 58,
                        child: CupertinoButton(
                          key: const ValueKey('new-message-attachment-button'),
                          minSize: 48,
                          padding: EdgeInsets.zero,
                          onPressed:
                              _busy ? null : _showCompactAttachmentMenu,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: MessagesPalette.fill(context),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              CupertinoIcons.plus,
                              size: 25,
                              color: MessagesPalette.secondaryLabel(context),
                            ),
                          ),
                        ),
                      )
                    else ...[
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
                    ],
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
                                              : (widget.enabled
                                                  ? _startRecording
                                                  : null),
                                          child: CupertinoButton(
                                            key: ValueKey(canSend),
                                            minSize: 34,
                                            padding: EdgeInsets.zero,
                                            onPressed: canSend
                                                ? _send
                                                : (_busy || !widget.enabled
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

  Widget _buildIos3Composer(
    BuildContext context, {
    required MessageAttachment? attachment,
    required bool isAudioDraft,
    required bool canSend,
  }) {
    final useGreenSend = AppSettingsScope.of(context).sentBubbleColor ==
        SentBubbleColor.green;
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEDEEF0), Color(0xFFC7C8CC)],
          ),
          border: Border(
            top: BorderSide(color: Color(0xFF8B8D92), width: 1),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (attachment?.kind == MessageAttachmentKind.image)
              _AttachmentPreview(
                attachment: attachment!,
                onRemove: _cancelRecording,
              ),
            SizedBox(
              height: 60,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(width: 8),
                  CupertinoButton(
                    key: const ValueKey('new-message-attachment-button'),
                    minSize: 40,
                    padding: EdgeInsets.zero,
                    onPressed: _busy ? null : _showCompactAttachmentMenu,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF878E9A), Color(0xFF5F6976)],
                        ),
                        border: Border.all(
                          color: const Color(0xFF383E47),
                          width: 1.2,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x8CFFFFFF),
                            blurRadius: 1,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        CupertinoIcons.camera_fill,
                        color: CupertinoColors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F6F6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF303030),
                          width: 1.1,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x70000000),
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                          BoxShadow(
                            color: Color(0x70FFFFFF),
                            blurRadius: 2,
                            offset: Offset(0, -1),
                          ),
                        ],
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
                              : CupertinoTextField(
                                  controller: _controller,
                                  focusNode: _focusNode,
                                  placeholder: 'iMessage',
                                  placeholderStyle: const TextStyle(
                                    fontFamily: 'SF Pro Text',
                                    color: Color(0xFF999999),
                                    fontSize: 17,
                                  ),
                                  style: const TextStyle(
                                    fontFamily: 'SF Pro Text',
                                    color: CupertinoColors.black,
                                    fontSize: 17,
                                  ),
                                  minLines: 1,
                                  maxLines: 1,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  keyboardType: TextInputType.multiline,
                                  decoration: null,
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    9,
                                    12,
                                    9,
                                  ),
                                ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton(
                    minSize: 40,
                    padding: EdgeInsets.zero,
                    onPressed: canSend && !_busy ? _send : null,
                    child: Container(
                      width: 87,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: canSend
                              ? (useGreenSend
                                  ? const [
                                      Color(0xFF61BB47),
                                      Color(0xFF009A4A),
                                    ]
                                  : const [
                                      Color(0xFF96B5F9),
                                      Color(0xFF1B46CC),
                                    ])
                              : const [Color(0xFFB9C3D8), Color(0xFF7083AD)],
                        ),
                        border: Border.all(
                          color: const Color(0xFF344B88),
                          width: 1.2,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x40FFFFFF),
                            blurRadius: 1,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Text(
                        'Send',
                        style: TextStyle(
                          color: Color(0xFFFFFFFB),
                          fontFamily: 'SF Pro Text',
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(
                              color: Color(0x52000000),
                              offset: Offset(0, -1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIos26Composer(
    BuildContext context,
    AppSettingsController settings, {
    required MessageAttachment? attachment,
    required bool isAudioDraft,
    required bool canSend,
  }) {
    final blur = settings.headerBlurSigma.clamp(0, 20).toDouble();
    return SafeArea(
      top: false,
      child: ColoredBox(
        color: MessagesPalette.background(context).withValues(alpha: .9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (attachment?.kind == MessageAttachmentKind.image)
              _AttachmentPreview(
                attachment: attachment!,
                onRemove: _cancelRecording,
              ),
            SizedBox(
              height: 66,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (!_recording && !isAudioDraft)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: LiquidGlassSurface(
                        borderRadius: BorderRadius.circular(20),
                        blurSigma: blur,
                        transparency: settings.headerTransparency,
                        child: SizedBox.square(
                          dimension: 40,
                          child: CupertinoButton(
                            key: const ValueKey(
                              'new-message-attachment-button',
                            ),
                            minSize: 40,
                            padding: EdgeInsets.zero,
                            onPressed: _busy ? null : _openMediaLibrary,
                            child: Icon(
                              CupertinoIcons.plus,
                              size: 25,
                              color: MessagesPalette.label(context)
                                  .withValues(alpha: .78),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 16),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LiquidGlassSurface(
                      borderRadius: BorderRadius.circular(20),
                      blurSigma: blur,
                      transparency: settings.headerTransparency,
                      child: SizedBox(
                        height: 40,
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
                                          attachment!.durationMilliseconds ??
                                              0,
                                    ),
                                    playing: _previewPlaying,
                                    onPlayPause: _togglePreviewPlayback,
                                    onCancel: _cancelRecording,
                                    onSend: _send,
                                  )
                                : Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: CupertinoTextField(
                                          controller: _controller,
                                          focusNode: _focusNode,
                                          placeholder: 'iMessage',
                                          placeholderStyle: TextStyle(
                                            fontFamily: 'SF Pro Text',
                                            color: MessagesPalette
                                                .secondaryLabel(context)
                                                .withValues(alpha: .55),
                                            fontSize: 17,
                                            height: 1.2,
                                          ),
                                          style: MessagesText.body(context),
                                          minLines: 1,
                                          maxLines: 1,
                                          textCapitalization:
                                              TextCapitalization.sentences,
                                          keyboardType:
                                              TextInputType.multiline,
                                          decoration: null,
                                          padding: const EdgeInsets.fromLTRB(
                                            18,
                                            8,
                                            4,
                                            8,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 38,
                                        height: 38,
                                        child: AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 140,
                                          ),
                                          child: GestureDetector(
                                            key: const ValueKey(
                                              'voice-message-button',
                                            ),
                                            onLongPress: canSend || _busy
                                                ? null
                                                : (widget.enabled
                                                    ? _startRecording
                                                    : null),
                                            child: CupertinoButton(
                                              key: ValueKey(canSend),
                                              minSize: 38,
                                              padding: EdgeInsets.zero,
                                              onPressed: canSend
                                                  ? _send
                                                  : (_busy || !widget.enabled
                                                      ? null
                                                      : _startRecording),
                                              child: canSend
                                                  ? const Icon(
                                                      CupertinoIcons
                                                          .arrow_up_circle_fill,
                                                      size: 32,
                                                      color: Color(0xFF0088FF),
                                                    )
                                                  : _VoiceWaveIcon(
                                                      color: MessagesPalette
                                                          .secondaryLabel(
                                                        context,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 1),
                                    ],
                                  ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
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
  const _MediaLibrarySheet({
    required this.loadPage,
    required this.pickFromGallery,
    required this.useIos26,
  });

  final Future<List<MessageAttachment>> Function(int offset) loadPage;
  final Future<MessageAttachment?> Function() pickFromGallery;
  final bool useIos26;

  @override
  State<_MediaLibrarySheet> createState() => _MediaLibrarySheetState();
}

class _MediaLibrarySheetState extends State<_MediaLibrarySheet> {
  static const _pageSize = 24;
  final _images = <MessageAttachment>[];
  final _scrollController = ScrollController();
  double _height = 296;
  bool _loading = false;
  bool _pickingFromGallery = false;
  bool _hasMore = true;
  int _nextOffset = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.useIos26) _height = 340;
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

  Future<void> _openFullGallery() async {
    if (_pickingFromGallery) return;
    setState(() {
      _pickingFromGallery = true;
      _error = null;
    });
    try {
      final image = await widget.pickFromGallery();
      if (!mounted || image == null) return;
      Navigator.pop(context, image);
    } catch (error) {
      if (!mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Photo Library Could Not Be Opened'),
          content: Text(error.toString()),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _pickingFromGallery = false);
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
    final showStatusTile = _loading || _error != null;
    final panelWidth = (MediaQuery.sizeOf(context).width - 12)
        .clamp(0.0, double.infinity)
        .toDouble();
    final ios26Spacing = ((panelWidth - 20 - 300) / 2)
        .clamp(6.0, 35.0)
        .toDouble();
    return GridView.builder(
      controller: _scrollController,
      padding: widget.useIos26
          ? const EdgeInsets.fromLTRB(10, 0, 10, 16)
          : const EdgeInsets.fromLTRB(6, 10, 6, 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: widget.useIos26 ? ios26Spacing : 6,
        mainAxisSpacing: widget.useIos26 ? 19 : 6,
        childAspectRatio: widget.useIos26 ? 1.0 : 122 / 117,
      ),
      itemCount: 1 + _images.length + (showStatusTile ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) {
          return CupertinoButton(
            key: const ValueKey('full-photo-library-picker'),
            padding: EdgeInsets.zero,
            onPressed: _pickingFromGallery ? null : _openFullGallery,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: MessagesPalette.fill(context),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Center(
                child: _pickingFromGallery
                    ? const CupertinoActivityIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.photo_on_rectangle,
                            size: 29,
                            color: MessagesPalette.blue,
                          ),
                          const SizedBox(height: 7),
                          const Text(
                            'Photo Library',
                            style: TextStyle(
                              fontFamily: 'SF Pro Text',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: MessagesPalette.blue,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          );
        }
        final imageIndex = index - 1;
        if (imageIndex == _images.length) {
          return Center(
            child: _error == null
                ? const CupertinoActivityIndicator(radius: 10)
                : CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _loadNextPage,
                    child: const Text('Try Again'),
                  ),
          );
        }
        final image = _images[imageIndex];
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
    final desiredMinimumHeight = widget.useIos26 ? 340.0 : 296.0;
    final minimumHeight = maximumHeight < desiredMinimumHeight
        ? maximumHeight
        : desiredMinimumHeight;
    final content = SizedBox(
      height: _height.clamp(minimumHeight, maximumHeight),
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
              height: widget.useIos26 ? 20 : 54,
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
                  if (!widget.useIos26)
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
    if (widget.useIos26) {
      final settings = AppSettingsScope.of(context);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: LiquidGlassSurface(
          borderRadius: BorderRadius.circular(34),
          blurSigma: settings.headerBlurSigma.clamp(0, 20).toDouble(),
          transparency: settings.headerTransparency,
          child: content,
        ),
      );
    }
    return Container(
      height: _height.clamp(minimumHeight, maximumHeight),
      decoration: BoxDecoration(
        color: MessagesPalette.background(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
      ),
      child: content,
    );
  }
}
