import 'package:flutter/material.dart';

import '../theme.dart';

/// A tag pill. [dense] is used inside list rows, the regular size elsewhere.
///
/// [colorValue] is an ARGB color from the tag manager. Passing 0 keeps the
/// theme default styling.
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.onRemove,
    this.dense = false,
    this.colorValue = 0,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Shows a close icon that removes the chip from the active filter row.
  final VoidCallback? onRemove;
  final bool dense;
  final int colorValue;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(999);
    final tagColor = colorValue == 0 ? null : Color(colorValue);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = tagColor == null
        ? (dense
              ? AppColors.tagBg
              : (selected ? AppColors.accentSoft : AppColors.tagBg))
        : Color.alphaBlend(
            tagColor.withValues(
              alpha: selected ? 0.20 : (dense ? 0.10 : 0.12),
            ),
            AppColors.tagBg,
          );
    final foreground = tagColor == null
        ? (dense
              ? AppColors.muted
              : (selected ? AppColors.accentInk : AppColors.ink2))
        : (dark
              ? Color.lerp(tagColor, Colors.white, 0.45)!
              : Color.lerp(tagColor, Colors.black, 0.18)!);
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: Container(
        padding: dense
            ? const EdgeInsets.symmetric(horizontal: 7, vertical: 2)
            : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: radius,
          border: dense
              ? null
              : Border.all(
                  color: tagColor == null
                      ? (selected ? AppColors.accent : AppColors.line)
                      : tagColor.withValues(alpha: dark ? 0.55 : 0.40),
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: dense ? 11 : 12, color: foreground),
            ),
            if (onRemove != null) ...[
              const SizedBox(width: 3),
              GestureDetector(
                onTap: onRemove,
                behavior: HitTestBehavior.opaque,
                child: Icon(Icons.close_rounded, size: 13, color: foreground),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
