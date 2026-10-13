import 'package:audioplayers/audioplayers.dart';

abstract final class MessageSounds {
  static final AudioPlayer _sentPlayer = AudioPlayer();
  static final AudioPlayer _receivedPlayer = AudioPlayer();

  static Future<void> playSent() =>
      _sentPlayer.play(AssetSource('sounds/SentMessage.m4a'));

  static Future<void> playReceived() =>
      _receivedPlayer.play(AssetSource('sounds/ReceivedMessage.m4a'));
}
