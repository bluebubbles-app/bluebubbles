class NotificationOpenRequest {
  const NotificationOpenRequest({
    required this.threadId,
    required this.sequence,
  });

  final String threadId;
  final int sequence;
}
