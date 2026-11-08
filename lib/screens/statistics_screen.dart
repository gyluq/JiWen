import 'package:flutter/material.dart';

import '../data/notes_db.dart';
import '../models/tag.dart';
import '../theme.dart';

/// Statistics panel (F-52): note total, unanswered count and tag split.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  int _total = 0;
  int _todo = 0;
  List<Tag> _tags = const [];

  @override
  void initState() {
    super.initState();
    final counts = NotesDb.instance.noteCounts();
    _total = counts.total;
    _todo = counts.todo;
    _tags = NotesDb.instance
        .listTags()
        .where((tag) => tag.noteCount > 0)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final maxCount = _tags.isEmpty ? 0 : _tags.first.noteCount;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
          color: AppColors.ink,
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Text(
          '统计',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _StatCard(
                  value: '$_total',
                  label: '笔记总数',
                  highlighted: false,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  value: '$_todo',
                  label: '待解答',
                  highlighted: true,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 22, 2, 8),
            child: Text(
              '标签分布',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: AppColors.ink2,
              ),
            ),
          ),
          if (_tags.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '给笔记添加标签后，这里会显示分布。',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            )
          else
            for (final tag in _tags) _TagBar(tag: tag, maxCount: maxCount),
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              '统计只包含未删除的笔记，标签按关联笔记数排序。',
              style: TextStyle(
                fontSize: 11,
                height: 1.7,
                color: AppColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.highlighted,
  });

  final String value;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.accentSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted ? AppColors.accent : AppColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              height: 1.1,
              letterSpacing: -0.5,
              color: highlighted ? AppColors.accentInk : AppColors.ink,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: highlighted
                  ? AppColors.accentInk.withValues(alpha: 0.8)
                  : AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagBar extends StatelessWidget {
  const _TagBar({required this.tag, required this.maxCount});

  final Tag tag;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final ratio = maxCount == 0 ? 0.0 : tag.noteCount / maxCount;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tag.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, color: AppColors.ink2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${tag.noteCount} 条',
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: AppColors.tagBg),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: ratio,
                      child: ColoredBox(color: AppColors.accent),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
