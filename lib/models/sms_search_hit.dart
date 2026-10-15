class SmsSearchHit {
  const SmsSearchHit({
    required this.threadId,
    required this.messageId,
    required this.text,
    required this.sentAt,
    required this.isFromMe,
  });

  final String threadId;
  final String messageId;
  final String text;
  final DateTime sentAt;
  final bool isFromMe;
}
