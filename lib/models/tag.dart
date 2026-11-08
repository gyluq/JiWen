class Tag {
  Tag({required this.id, required this.name, this.noteCount = 0});

  factory Tag.fromRow(Map<String, Object?> row) {
    return Tag(
      id: row['id'] as String,
      name: row['name'] as String,
      noteCount: (row['note_count'] as int?) ?? 0,
    );
  }

  final String id;
  final String name;
  final int noteCount;
}
