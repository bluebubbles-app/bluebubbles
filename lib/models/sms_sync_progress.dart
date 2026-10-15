class SmsSyncProgress {
  const SmsSyncProgress({
    required this.active,
    required this.cachedMessages,
    required this.totalMessages,
  });

  static const idle = SmsSyncProgress(
    active: false,
    cachedMessages: 0,
    totalMessages: 0,
  );

  final bool active;
  final int cachedMessages;
  final int totalMessages;

  double get fraction {
    if (totalMessages <= 0) return 0;
    return (cachedMessages / totalMessages).clamp(0.0, 1.0).toDouble();
  }
}
