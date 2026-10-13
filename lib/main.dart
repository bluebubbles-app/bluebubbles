import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';

import 'data/demo_data.dart';
import 'data/message_repository.dart';
import 'models/conversation.dart';
import 'screens/conversation_list_screen.dart';
import 'settings/app_settings.dart';
import 'theme/messages_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const MessagesUiApp());
}

class MessagesUiApp extends StatefulWidget {
  const MessagesUiApp({super.key});

  @override
  State<MessagesUiApp> createState() => _MessagesUiAppState();
}

class _MessagesUiAppState extends State<MessagesUiApp> {
  late final MessageRepository _messageRepository =
      DemoMessageRepository(demoConversations());
  final AppSettingsController _settings = AppSettingsController();

  @override
  void initState() {
    super.initState();
    _settings.load();
  }

  @override
  void dispose() {
    _settings.dispose();
    super.dispose();
  }

  void _sendMessage(Conversation conversation, String text) {
    setState(() => _messageRepository.sendMessage(conversation, text));
  }

  void _replaceConversations(List<Conversation> conversations) {
    setState(() => _messageRepository.replaceAll(conversations));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) => AppSettingsScope(
        controller: _settings,
        child: CupertinoApp(
          title: 'BlueBubbles',
          debugShowCheckedModeBanner: false,
          locale: _settings.locale,
          supportedLocales: const [Locale('en'), Locale('fr')],
          localizationsDelegates: const [
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: TextScaler.linear(_settings.fontScale),
              ),
              child: child!,
            );
          },
          theme: CupertinoThemeData(
            primaryColor: MessagesPalette.blue,
            textTheme: CupertinoTextThemeData(
              textStyle: TextStyle(
                fontFamily: 'SF Pro Text',
                fontFamilyFallback: const ['Noto Color Emoji'],
              ),
            ),
            applyThemeToAll: true,
          ),
          home: ConversationListScreen(
            conversations: _messageRepository.conversations,
            onSend: _sendMessage,
            onReplaceConversations: _replaceConversations,
          ),
        ),
      ),
    );
  }
}
