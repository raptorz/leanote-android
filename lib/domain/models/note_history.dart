class NoteHistory {
  const NoteHistory({
    required this.id,
    required this.updatedTime,
    required this.updatedUserId,
    this.isMarkdown = false,
  });
  final String id;
  final String updatedTime;
  final String updatedUserId;
  final bool isMarkdown;

  factory NoteHistory.fromJson(Map<String, Object?> json) {
    final id = json['HistoryId'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('missingHistoryId');
    }
    return NoteHistory(
      id: id,
      updatedTime: json['UpdatedTime']?.toString() ?? '',
      updatedUserId: json['UpdatedUserId']?.toString() ?? '',
      isMarkdown: json['IsMarkdown'] == true,
    );
  }
}
