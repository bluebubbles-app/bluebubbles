import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'data/demo_data.dart';
import 'models/conversation.dart';
import 'screens/conversation_list_screen.dart';
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
  final List<Conversation> _conversations = demoConversations();

  void _sendMessage(Conversation conversation, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      conversation.messages.add(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: trimmed,
          sentAt: DateTime.now(),
          isFromMe: true,
          deliveryState: DeliveryState.delivered,
        ),
      );
      conversation.preview = trimmed;
      conversation.updatedAt = DateTime.now();
      conversation.unreadCount = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'BlueBubbles',
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(
        primaryColor: MessagesPalette.blue,
        textTheme: CupertinoTextThemeData(
          textStyle: TextStyle(fontFamily: 'SF Pro Text'),
        ),
        applyThemeToAll: true,
      ),
      home: ConversationListScreen(
        conversations: _conversations,
        onSend: _sendMessage,
      ),
    );
  }
}
