class Account {
  const Account({
    required this.userId,
    required this.server,
    required this.username,
    required this.email,
    required this.logo,
  });

  final String userId;
  final Uri server;
  final String username;
  final String email;
  final String logo;

  /// Stable local-cache identity. Server user IDs are only unique within one
  /// Gemsnote installation, so the server origin must be part of the key.
  String get cacheKey => '${server.toString()}#$userId';

  factory Account.fromJson(Map<String, Object?> json, {required Uri server}) {
    final userId = json['UserId']?.toString() ?? '';
    if (userId.isEmpty) throw const FormatException('UserId is required');
    return Account(
      userId: userId,
      server: server,
      username: json['Username']?.toString() ?? '',
      email: json['Email']?.toString() ?? '',
      logo: json['Logo']?.toString() ?? '',
    );
  }
}
