enum NoteStatus {
  todo('todo'),
  done('done');

  const NoteStatus(this.value);
  final String value;

  static NoteStatus fromValue(String value) {
    return value == 'done' ? NoteStatus.done : NoteStatus.todo;
  }
}

class Note {
  Note({
    required this.id,
    this.title = '',
    this.body = '',
    this.status = NoteStatus.todo,
    this.pinned = false,
    this.favorite = false,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory Note.fromRow(Map<String, Object?> row) {
    return Note(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      body: row['body'] as String? ?? '',
      status: NoteStatus.fromValue(row['status'] as String? ?? 'todo'),
      pinned: (row['pinned'] as int? ?? 0) == 1,
      favorite: (row['favorite'] as int? ?? 0) == 1,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
      deletedAt: row['deleted_at'] as int?,
    );
  }

  final String id;
  String title;
  String body;
  NoteStatus status;
  bool pinned;
  bool favorite;
  final int createdAt;
  int updatedAt;

  /// Epoch ms when the note entered the recycle bin; null when live.
  int? deletedAt;
}
