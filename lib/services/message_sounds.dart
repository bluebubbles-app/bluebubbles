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
  static final Future<void> _sentReady =
      _sentPlayer.setAudioContext(_effectContext);
  static final Future<void> _receivedReady =
      _receivedPlayer.setAudioContext(_effectContext);

  static Future<void> playSent() async {
    await _sentReady;
    await _sentPlayer.play(AssetSource('sounds/SentMessage.m4a'));
  }

  static Future<void> playReceived() async {
    await _receivedReady;
    await _receivedPlayer.play(AssetSource('sounds/ReceivedMessage.m4a'));
  }
}
