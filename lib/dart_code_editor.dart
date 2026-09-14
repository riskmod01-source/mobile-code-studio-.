import 'package:flutter/material.dart';

/// A TextEditingController that paints Dart syntax highlighting by
/// building a styled TextSpan instead of plain text. This avoids pulling
/// in an external highlighting package, keeping the editor self-contained.
class DartSyntaxController extends TextEditingController {
  DartSyntaxController({super.text});

  static final _keywordPattern = RegExp(
    r'\b(abstract|class|extends|implements|import|export|final|const|var|'
    r'void|return|if|else|for|while|do|switch|case|break|continue|new|'
    r'this|super|static|async|await|Future|late|required|null|true|false|'
    r'enum|mixin|with|is|as|try|catch|finally|throw|typedef)\b',
  );
  static final _typePattern = RegExp(
    r'\b([A-Z][A-Za-z0-9_]*)\b',
  );
  static final _stringPattern = RegExp(r"""('([^'\\]|\\.)*')|("([^"\\]|\\.)*")""");
  static final _commentPattern = RegExp(r'//.*');
  static final _numberPattern = RegExp(r'\b\d+\.?\d*\b');

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final source = text;
    final spans = <TextSpan>[];
    final base = style ?? const TextStyle();

    // Merge all pattern matches, tagged by type, then sort and emit spans.
    final matches = <_Match>[];
    for (final m in _commentPattern.allMatches(source)) {
      matches.add(_Match(m.start, m.end, _TokenType.comment));
    }
    for (final m in _stringPattern.allMatches(source)) {
      matches.add(_Match(m.start, m.end, _TokenType.string));
    }
    for (final m in _keywordPattern.allMatches(source)) {
      matches.add(_Match(m.start, m.end, _TokenType.keyword));
    }
    for (final m in _numberPattern.allMatches(source)) {
      matches.add(_Match(m.start, m.end, _TokenType.number));
    }
    for (final m in _typePattern.allMatches(source)) {
      matches.add(_Match(m.start, m.end, _TokenType.type));
    }

    // Resolve overlaps: earlier-added categories (comment/string/keyword)
    // win over later ones (type), and longer/earlier spans win over later.
    matches.sort((a, b) => a.start != b.start
        ? a.start.compareTo(b.start)
        : b.end.compareTo(a.end));

    int cursor = 0;
    for (final m in matches) {
      if (m.start < cursor) continue; // overlaps something already emitted
      if (m.start > cursor) {
        spans.add(TextSpan(text: source.substring(cursor, m.start), style: base));
      }
      spans.add(TextSpan(
        text: source.substring(m.start, m.end),
        style: base.merge(_styleFor(m.type)),
      ));
      cursor = m.end;
    }
    if (cursor < source.length) {
      spans.add(TextSpan(text: source.substring(cursor), style: base));
    }

    return TextSpan(style: base, children: spans);
  }

  TextStyle _styleFor(_TokenType type) {
    switch (type) {
      case _TokenType.keyword:
        return const TextStyle(color: Color(0xFFCF8E6D), fontWeight: FontWeight.w600);
      case _TokenType.type:
        return const TextStyle(color: Color(0xFF56A8F5));
      case _TokenType.string:
        return const TextStyle(color: Color(0xFF6AAB73));
      case _TokenType.comment:
        return const TextStyle(color: Color(0xFF7A7E85), fontStyle: FontStyle.italic);
      case _TokenType.number:
        return const TextStyle(color: Color(0xFF2AACB8));
    }
  }
}

enum _TokenType { keyword, type, string, comment, number }

class _Match {
  final int start;
  final int end;
  final _TokenType type;
  _Match(this.start, this.end, this.type);
}

/// The editor panel: line-number gutter + highlighted, editable code area.
class DartCodeEditor extends StatefulWidget {
  const DartCodeEditor({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<DartCodeEditor> createState() => _DartCodeEditorState();
}

class _DartCodeEditorState extends State<DartCodeEditor> {
  final ScrollController _lineScroll = ScrollController();
  final ScrollController _codeScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _codeScroll.addListener(() {
      if (_lineScroll.hasClients) {
        _lineScroll.jumpTo(_codeScroll.offset);
      }
    });
    widget.controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _lineScroll.dispose();
    _codeScroll.dispose();
    super.dispose();
  }

  int get _lineCount => '\n'.allMatches(widget.controller.text).length + 1;

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13.5,
      height: 1.5,
      color: Color(0xFFD4D4D4),
    );

    return Container(
      color: const Color(0xFF1E1E1E),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line-number gutter, scroll-synced with the editor.
          Container(
            width: 44,
            padding: const EdgeInsets.only(top: 12),
            color: const Color(0xFF252526),
            child: ListView.builder(
              controller: _lineScroll,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _lineCount,
              itemBuilder: (context, i) => SizedBox(
                height: textStyle.fontSize! * textStyle.height!,
                child: Text(
                  '${i + 1}',
                  textAlign: TextAlign.right,
                  style: textStyle.copyWith(color: const Color(0xFF6E7681)),
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _codeScroll,
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: widget.controller,
                maxLines: null,
                style: textStyle,
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
                inputFormatters: const [], // plain text in, styled span out
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                enableSuggestions: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
