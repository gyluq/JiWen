import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../models/note.dart';
import '../models/tag.dart';
import '../theme.dart';
import '../util/search_highlight.dart';
import '../util/time_text.dart';
import 'tag_chip.dart';

/// One row of the note list, shared by the home list and search results.
///
/// Row height and excerpt length follow the list density setting (F-31/F-32):
/// the compact default keeps eight to nine notes on a phone screen.
class NoteListTile extends StatelessWidget {
  const NoteListTile({
    super.key,
    required this.note,
    this.tags = const [],
    this.query = '',
    this.onTap,
    this.onLongPress,
    this.onTagTap,
  });

  final Note note;
  final List<Tag> tags;

  /// Search term used for snippet windowing and keyword highlighting.
  final String query;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<Tag>? onTagTap;

  TextStyle get _titleStyle => TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.4,
    letterSpacing: -0.2,
    color: AppColors.ink,
  );

  TextStyle get _excerptStyle => TextStyle(
    fontSize: 12.5 * AppSettings.instance.bodyScale,
    height: 1.5,
    color: AppColors.muted,
  );

  TextSpan _highlighted(String text, TextStyle style) {
    if (query.trim().isEmpty) return TextSpan(text: text, style: style);
    return TextSpan(
      children: [
        for (final run in highlightRuns(text, query))
          TextSpan(
            text: run.text,
            style: run.isHit
                ? style.copyWith(
                    color: AppColors.accentInk,
                    backgroundColor: AppColors.accentSoft,
                  )
                : style,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = note.title.isEmpty ? '无标题' : note.title;
    final excerpt = searchSnippet(note.body, query);
    final density = AppSettings.instance.listDensity;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: density.verticalPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              _highlighted(title, _titleStyle),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _titleStyle,
            ),
            if (excerpt.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text.rich(
                _highlighted(excerpt, _excerptStyle),
                maxLines: density.excerptLines,
                overflow: TextOverflow.ellipsis,
                style: _excerptStyle,
              ),
            ],
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final tag in tags)
                        TagChip(
                          label: tag.name,
                          dense: true,
                          onTap: onTagTap == null ? null : () => onTagTap!(tag),
                        ),
                      _StatusPill(note: note),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatListTime(note.updatedAt),
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final todo = note.status == NoteStatus.todo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: todo ? AppColors.accentSoft : AppColors.tagBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        todo ? '待解答' : '已解答',
        style: TextStyle(
          fontSize: 11,
          color: todo ? AppColors.accentInk : AppColors.muted,
        ),
      ),
    );
  }
}
