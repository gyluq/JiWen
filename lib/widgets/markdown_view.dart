import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_settings.dart';
import '../data/attachments.dart';
import '../theme.dart';
import '../util/markdown_parser.dart';
import '../util/search_highlight.dart';

/// Renders the parsed Markdown subset as a single column of blocks.
///
/// Used by the editor preview. The detail screen composes its own lazily built
/// list out of [MarkdownBlockView] so it can jump to a heading or a search hit
/// (F-33 / F-57).
class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final document = parseMarkdown(source);
    if (document.isEmpty) {
      return Text(
        '还没有正文内容',
        style: TextStyle(fontSize: 13, color: AppColors.muted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in document.blocks) MarkdownBlockView(block: block),
      ],
    );
  }
}

/// Renders one Markdown block.
///
/// A block is its own widget so the reading list can build it lazily and
/// scroll to any of them by index. Each block owns the gesture recognizers it
/// creates and disposes them with itself.
class MarkdownBlockView extends StatefulWidget {
  const MarkdownBlockView({
    super.key,
    required this.block,
    this.highlight = '',
  });

  final MdBlock block;

  /// Search keyword painted with the accent (F-28).
  final String highlight;

  @override
  State<MarkdownBlockView> createState() => _MarkdownBlockViewState();
}

class _MarkdownBlockViewState extends State<MarkdownBlockView> {
  /// Link recognizers are cached per URL so rebuilds do not accumulate.
  final Map<String, TapGestureRecognizer> _linkRecognizers = {};

  @override
  void dispose() {
    for (final recognizer in _linkRecognizers.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _recognizerFor(BuildContext context, String url) {
    return _linkRecognizers.putIfAbsent(
      url,
      () => TapGestureRecognizer()..onTap = () => _openLink(context, url),
    );
  }

  /// Opens the link in the system browser (F-17); a failed launch falls back
  /// to copying the URL so the user never loses it.
  Future<void> _openLink(BuildContext context, String url) async {
    var launched = false;
    final uri = Uri.tryParse(url.trim());
    if (uri != null) {
      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        launched = false;
      }
    }
    if (!launched && context.mounted) {
      _copy(context, url, '无法打开链接，已复制');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          _buildBlock(context, widget.block, constraints.maxWidth),
    );
  }

  Widget _buildBlock(BuildContext context, MdBlock block, double maxWidth) {
    switch (block) {
      case MdHeading(:final level, :final children):
        final style = _headingStyle(level);
        return Padding(
          padding: EdgeInsets.only(top: level == 1 ? 6 : 20, bottom: 7),
          child: Text.rich(
            TextSpan(children: _buildSpans(context, children, style)),
            style: style,
          ),
        );
      case MdParagraph(children: [MdImage(:final url)]):
        // An image on its own line renders as a media block (F-14).
        return _buildImageBlock(context, url, maxWidth);
      case MdParagraph(:final children):
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text.rich(
            TextSpan(children: _buildSpans(context, children, _bodyStyle)),
            style: _bodyStyle,
          ),
        );
      case MdListBlock(:final ordered, :final items):
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: items
                .map((item) => _buildListItem(context, item, ordered))
                .toList(),
          ),
        );
      case MdCodeBlock(:final code, :final language):
        return _buildCodeBlock(context, code, language);
      case MdQuote(:final children):
        return Container(
          margin: const EdgeInsets.only(top: 4, bottom: 14),
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.accent, width: 2)),
          ),
          child: Text.rich(
            TextSpan(children: _buildSpans(context, children, _quoteStyle)),
            style: _quoteStyle,
          ),
        );
    }
  }

  Widget _buildListItem(BuildContext context, MdListItem item, bool ordered) {
    final indent = item.indent == 0 ? 0.0 : 18.0;
    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: ordered ? 24 : 16,
            child: ordered
                ? Text(
                    '${item.number ?? 0}.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.7,
                      color: AppColors.muted,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: 9),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.muted,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: _buildSpans(context, item.children, _listStyle),
              ),
              style: _listStyle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeBlock(BuildContext context, String code, String? language) {
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
            child: Row(
              children: [
                Text(
                  language == null ? '代码' : language.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.1,
                    color: AppColors.muted,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _copy(context, code, '已复制代码'),
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  color: AppColors.muted,
                  tooltip: '复制代码',
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text.rich(
              TextSpan(children: _highlightSpans(code, _codeStyle)),
              style: _codeStyle,
            ),
          ),
        ],
      ),
    );
  }

  List<InlineSpan> _buildSpans(
    BuildContext context,
    List<MdInline> inline,
    TextStyle base,
  ) {
    final spans = <InlineSpan>[];
    for (final item in inline) {
      switch (item) {
        case MdText(:final text):
          spans.addAll(_textSpans(context, text, base));
        case MdStrong(:final children):
          spans.add(
            TextSpan(
              children: _buildSpans(context, children, base),
              style: base.copyWith(fontWeight: FontWeight.w700),
            ),
          );
        case MdEmphasis(:final children):
          spans.add(
            TextSpan(
              children: _buildSpans(context, children, base),
              style: base.copyWith(fontStyle: FontStyle.italic),
            ),
          );
        case MdCodeSpan(:final code):
          spans.addAll(
            _highlightSpans(
              code,
              base.copyWith(
                fontFamily: 'monospace',
                fontSize: base.fontSize! - 1,
                backgroundColor: AppColors.tagBg,
                color: AppColors.ink,
              ),
            ),
          );
        case MdLink(:final label, :final url):
          final linkStyle = base.copyWith(
            color: AppColors.accentInk,
            decoration: TextDecoration.underline,
            decorationColor: AppColors.accentSoft,
          );
          spans.addAll(
            _linkSpans(
              _buildSpans(context, label, linkStyle),
              _recognizerFor(context, url),
            ),
          );
        case MdImage(:final alt, :final url):
          final label = alt.isNotEmpty ? alt : url;
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _buildImageChip(label),
            ),
          );
      }
    }
    return spans;
  }

  /// Flutter resolves a tap to the span that actually holds the text, so a
  /// recognizer attached to a container span never fires. Push the link
  /// recognizer down to every leaf span instead.
  List<InlineSpan> _linkSpans(
    List<InlineSpan> spans,
    TapGestureRecognizer recognizer,
  ) {
    return [
      for (final span in spans)
        if (span is TextSpan)
          TextSpan(
            text: span.text,
            style: span.style,
            semanticsLabel: span.semanticsLabel,
            recognizer: recognizer,
            children: span.children == null
                ? null
                : _linkSpans(span.children!, recognizer),
          )
        else
          span,
    ];
  }

  /// Plain text may contain a bare URL; it becomes tappable like a Markdown
  /// link (F-17). Trailing punctuation stays outside the link.
  static final RegExp _bareUrl = RegExp(r'https?://[^\s<>()\[\]{}]+');

  List<InlineSpan> _textSpans(
    BuildContext context,
    String text,
    TextStyle base,
  ) {
    final matches = _bareUrl.allMatches(text);
    if (matches.isEmpty) return _highlightSpans(text, base);
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.addAll(_highlightSpans(text.substring(cursor, match.start), base));
      }
      final raw = match.group(0)!;
      final url = raw.replaceFirst(RegExp(r'[.,;:!?，。；：！？]+$'), '');
      spans.add(
        TextSpan(
          text: url,
          style: base.copyWith(
            color: AppColors.accentInk,
            decoration: TextDecoration.underline,
            decorationColor: AppColors.accentSoft,
          ),
          recognizer: _recognizerFor(context, url),
        ),
      );
      if (raw.length > url.length) {
        spans.addAll(_highlightSpans(raw.substring(url.length), base));
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.addAll(_highlightSpans(text.substring(cursor), base));
    }
    return spans;
  }

  List<InlineSpan> _highlightSpans(String text, TextStyle base) {
    final keyword = widget.highlight.trim();
    if (keyword.isEmpty) return [TextSpan(text: text, style: base)];
    return [
      for (final run in highlightRuns(text, keyword))
        TextSpan(
          text: run.text,
          style: run.isHit
              ? base.copyWith(
                  color: AppColors.accentInk,
                  backgroundColor: AppColors.accentSoft,
                )
              : base,
        ),
    ];
  }

  /// Renders an image that occupies its own paragraph.
  Widget _buildImageBlock(
    BuildContext context,
    String reference,
    double maxWidth,
  ) {
    final file = AttachmentStore.instance.resolve(reference);
    if (file == null) return _buildImageChip('图片');
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 14),
      child: GestureDetector(
        onTap: () => _openImage(context, file),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            file,
            width: maxWidth,
            fit: BoxFit.fitWidth,
            errorBuilder: (context, error, stackTrace) =>
                _buildImageChip('图片已丢失'),
          ),
        ),
      ),
    );
  }

  Widget _buildImageChip(String label) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.tagBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 13, color: AppColors.muted),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  void _openImage(BuildContext context, File file) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (dialogContext) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(dialogContext).pop(),
          child: InteractiveViewer(
            maxScale: 4,
            child: Center(
              child: Image.file(
                file,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Text(
                  '图片已丢失',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _copy(BuildContext context, String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(fontSize: 13)),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1400),
        ),
      );
  }

  TextStyle _headingStyle(int level) {
    return switch (level) {
      1 => TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.36,
        letterSpacing: -0.4,
        color: AppColors.ink,
      ),
      2 => TextStyle(
        fontSize: 18.5,
        fontWeight: FontWeight.w600,
        height: 1.45,
        letterSpacing: -0.1,
        color: AppColors.accentInk,
      ),
      _ => TextStyle(
        fontSize: 16.5,
        fontWeight: FontWeight.w600,
        height: 1.5,
        color: AppColors.ink2,
      ),
    };
  }

  TextStyle get _bodyStyle => TextStyle(
    fontSize: 15 * AppSettings.instance.bodyScale,
    height: 1.82,
    letterSpacing: 0.1,
    color: AppColors.ink,
  );

  TextStyle get _listStyle => TextStyle(
    fontSize: 14.5 * AppSettings.instance.bodyScale,
    height: 1.7,
    color: AppColors.ink2,
  );

  TextStyle get _codeStyle => TextStyle(
    fontFamily: 'monospace',
    fontSize: 13,
    height: 1.6,
    color: AppColors.ink2,
  );

  TextStyle get _quoteStyle => TextStyle(
    fontSize: 14.5 * AppSettings.instance.bodyScale,
    height: 1.75,
    color: AppColors.ink2,
  );
}
