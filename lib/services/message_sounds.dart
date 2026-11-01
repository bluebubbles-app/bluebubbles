import 'package:audioplayers/audioplayers.dart';

abstract final class MessageSounds {
  static final AudioPlayer _sentPlayer = AudioPlayer();
  static final AudioPlayer _receivedPlayer = AudioPlayer();
  static final AudioContext _effectContext = AudioContext(
    android: AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.assistanceSonification,
      audioFocus: AndroidAudioFocus.none,
    ),
  );
  static Future<void> playSent() => _sentPlayer.play(
        AssetSource('sounds/SentMessage.m4a'),
        ctx: _effectContext,
      );

  static Future<void> playReceived() => _receivedPlayer.play(
        AssetSource('sounds/ReceivedMessage.m4a'),
        ctx: _effectContext,
      );
}
