class BannedEntry {
  BannedEntry({
    required this.username,
    required this.ipAddress,
    required this.reason,
    required this.bannedAt,
    required this.bannedUntil,
  });

  final String username;
  final String ipAddress;
  final String reason;
  final DateTime bannedAt;
  final DateTime bannedUntil;

  bool get isActive => DateTime.now().isBefore(bannedUntil);

  Duration get remainingTime {
    final now = DateTime.now();
    return bannedUntil.isAfter(now) ? bannedUntil.difference(now) : Duration.zero;
  }
}