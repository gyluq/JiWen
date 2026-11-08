import 'package:flutter/material.dart';

import '../theme.dart';

/// A tag pill. [dense] is used inside list rows, the regular size elsewhere.
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.onRemove,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Shows a close icon that removes the chip from the active filter row.
  final VoidCallback? onRemove;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(999);
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: Container(
        padding: dense
            ? const EdgeInsets.symmetric(horizontal: 7, vertical: 2)
            : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: dense
              ? AppColors.tagBg
              : (selected ? AppColors.accentSoft : AppColors.tagBg),
          borderRadius: radius,
          border: dense
              ? null
              : Border.all(color: selected ? AppColors.accent : AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: dense ? 11 : 12,
                color: dense
                    ? AppColors.muted
                    : (selected ? AppColors.accentInk : AppColors.ink2),
              ),
            ),
            if (onRemove != null) ...[
              const SizedBox(width: 3),
              GestureDetector(
                onTap: onRemove,
                behavior: HitTestBehavior.opaque,
                child: Icon(
                  Icons.close_rounded,
                  size: 13,
                  color: selected ? AppColors.accentInk : AppColors.ink2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
