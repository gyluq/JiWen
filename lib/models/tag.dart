class Tag {
  Tag({
    required this.id,
    required this.name,
    this.noteCount = 0,
    this.color = 0,
  });

  factory Tag.fromRow(Map<String, Object?> row) {
    return Tag(
      id: row['id'] as String,
      name: row['name'] as String,
      noteCount: (row['note_count'] as int?) ?? 0,
      color: (row['color'] as int?) ?? 0,
    );
  }

  final String id;
  final String name;
  final int noteCount;

  /// ARGB color chosen in the tag manager, 0 for the theme default.
  final int color;

  Tag copyWith({String? name, int? noteCount, int? color}) {
    return Tag(
      id: id,
      name: name ?? this.name,
      noteCount: noteCount ?? this.noteCount,
      color: color ?? this.color,
    );
  }
}
