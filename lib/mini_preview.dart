import 'package:flutter/material.dart';

/// A deliberately small "live preview" engine.
///
/// Running arbitrary Dart/Flutter source on-device isn't possible without
/// embedding a full Dart VM + Flutter engine (which is effectively what
/// the "Build APK" pipeline does via GitHub Actions). Instead, this widget
/// recognizes a common, constrained subset of widget-construction syntax
/// — Text, Container, Column, Row, Center, Padding, Icon, ElevatedButton —
/// and renders an approximate live preview as you type. Anything it can't
/// confidently parse falls back to a friendly "can't preview this" message
/// rather than guessing.
class MiniPreview extends StatelessWidget {
  const MiniPreview({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    try {
      final body = _extractBuildReturn(source);
      if (body == null) {
        return _fallback('No build() return statement found yet.');
      }
      final parser = _WidgetParser(body);
      final widget = parser.parseWidget();
      if (widget == null) {
        return _fallback('This code uses widgets the live preview '
            "doesn't recognize yet — try Build APK for the real render.");
      }
      return Container(
        color: Colors.white,
        alignment: Alignment.topLeft,
        padding: const EdgeInsets.all(16),
        child: widget,
      );
    } catch (_) {
      return _fallback('Could not parse this code for preview.');
    }
  }

  Widget _fallback(String message) => Container(
        color: Colors.white,
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.visibility_off_outlined, size: 32, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );

  /// Grabs the expression after the first `return` inside a `build(...)`
  /// method, up to its matching semicolon. Very approximate on purpose.
  String? _extractBuildReturn(String src) {
    final buildIndex = src.indexOf('Widget build(');
    if (buildIndex == -1) return null;
    final returnIndex = src.indexOf('return', buildIndex);
    if (returnIndex == -1) return null;
    final start = returnIndex + 'return'.length;
    final end = src.indexOf(';\n  }', start);
    final fallbackEnd = end == -1 ? src.lastIndexOf(';') : end;
    if (fallbackEnd == -1 || fallbackEnd <= start) return null;
    return src.substring(start, fallbackEnd).trim();
  }
}

/// A minimal recursive-descent parser for expressions shaped like
/// `Widget(arg: value, child: Widget(...), children: [Widget(...), ...])`.
class _WidgetParser {
  _WidgetParser(String input) : _s = input, _i = 0;
  final String _s;
  int _i;

  void _skipWs() {
    while (_i < _s.length && _s[_i].trim().isEmpty) _i++;
  }

  bool _consume(String token) {
    _skipWs();
    if (_s.startsWith(token, _i)) {
      _i += token.length;
      return true;
    }
    return false;
  }

  String _readIdentifier() {
    _skipWs();
    final start = _i;
    while (_i < _s.length && RegExp(r'[A-Za-z0-9_]').hasMatch(_s[_i])) {
      _i++;
    }
    return _s.substring(start, _i);
  }

  String? _readStringLiteral() {
    _skipWs();
    if (_i >= _s.length || (_s[_i] != "'" && _s[_i] != '"')) return null;
    final quote = _s[_i];
    final start = ++_i;
    while (_i < _s.length && _s[_i] != quote) {
      if (_s[_i] == r'\') _i++;
      _i++;
    }
    final value = _s.substring(start, _i);
    _i++; // closing quote
    return value;
  }

  /// Parses one `Identifier(args)` widget call, or a string/list literal
  /// used inline. Returns null if the shape isn't recognized.
  Widget? parseWidget() {
    _skipWs();
    final name = _readIdentifier();
    if (name.isEmpty || !_consume('(')) return null;
    final args = _parseArgs();
    _consume(')');
    return _build(name, args);
  }

  /// Parses a comma-separated arg list into name->rawValue pairs. Values
  /// are kept lazily as parseable substrings via recursive calls when
  /// consumed in `_build`.
  Map<String, _ArgValue> _parseArgs() {
    final args = <String, _ArgValue>{};
    int positional = 0;
    while (true) {
      _skipWs();
      if (_i >= _s.length || _s[_i] == ')') break;
      final beforeName = _i;
      var name = _readIdentifier();
      _skipWs();
      if (name.isNotEmpty && _consume(':')) {
        args[name] = _parseValue();
      } else {
        _i = beforeName;
        args['_pos${positional++}'] = _parseValue();
      }
      _skipWs();
      if (!_consume(',')) break;
    }
    return args;
  }

  _ArgValue _parseValue() {
    _skipWs();
    if (_i < _s.length && _s[_i] == "'" || (_i < _s.length && _s[_i] == '"')) {
      return _ArgValue.string(_readStringLiteral() ?? '');
    }
    if (_i < _s.length && _s[_i] == '[') {
      _i++; // consume '['
      final widgets = <Widget>[];
      while (true) {
        _skipWs();
        if (_i >= _s.length || _s[_i] == ']') break;
        final w = parseWidget();
        if (w != null) widgets.add(w);
        _skipWs();
        if (!_consume(',')) break;
      }
      _consume(']');
      return _ArgValue.list(widgets);
    }
    // Otherwise assume it's a nested widget call or a bare identifier
    // (e.g. a color constant name) — try widget parse, else raw token.
    final start = _i;
    final maybeWidget = parseWidget();
    if (maybeWidget != null) return _ArgValue.widget(maybeWidget);
    _i = start;
    return _ArgValue.raw(_readIdentifier());
  }

  Widget? _build(String name, Map<String, _ArgValue> args) {
    Widget? child() => args['child']?.widget;
    List<Widget> children() => args['children']?.list ?? const [];
    String? text() => args['_pos0']?.string ?? args['text']?.string;

    switch (name) {
      case 'Text':
        return Text(text() ?? '', style: const TextStyle(color: Colors.black87));
      case 'Icon':
        return const Icon(Icons.star, color: Colors.amber);
      case 'Center':
        return Center(child: child() ?? const SizedBox());
      case 'Padding':
        return Padding(padding: const EdgeInsets.all(8), child: child());
      case 'Container':
        return Container(
          padding: const EdgeInsets.all(8),
          color: _colorFor(args['color']?.raw),
          child: child(),
        );
      case 'Column':
        return Column(mainAxisSize: MainAxisSize.min, children: children());
      case 'Row':
        return Row(mainAxisSize: MainAxisSize.min, children: children());
      case 'ElevatedButton':
        return ElevatedButton(
          onPressed: () {},
          child: child() ?? Text(text() ?? 'Button'),
        );
      case 'SizedBox':
        return const SizedBox(height: 8, width: 8);
      default:
        return null;
    }
  }

  Color? _colorFor(String? name) {
    switch (name) {
      case 'blue':
        return Colors.blue.withOpacity(0.15);
      case 'red':
        return Colors.red.withOpacity(0.15);
      case 'green':
        return Colors.green.withOpacity(0.15);
      case 'grey':
      case 'gray':
        return Colors.grey.withOpacity(0.2);
      default:
        return Colors.black.withOpacity(0.04);
    }
  }
}

/// A tagged-union-ish value holder so `_parseArgs` can return heterogeneous
/// results (widgets, strings, lists of widgets, raw identifiers) without
/// needing `dynamic` scattered through the parser.
class _ArgValue {
  _ArgValue._(this.widget, this.string, this.list, this.raw);
  final Widget? widget;
  final String? string;
  final List<Widget>? list;
  final String? raw;

  factory _ArgValue.widget(Widget w) => _ArgValue._(w, null, null, null);
  factory _ArgValue.string(String s) => _ArgValue._(null, s, null, null);
  factory _ArgValue.list(List<Widget> l) => _ArgValue._(null, null, l, null);
  factory _ArgValue.raw(String r) => _ArgValue._(null, null, null, r);
}
