import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/studio_state.dart';
import '../widgets/dart_code_editor.dart';
import '../widgets/mini_preview.dart';
import '../widgets/build_apk_sheet.dart';

/// Top-level screen: a resizable split between the code editor and the
/// live preview panel, with a "Build APK" action that kicks off the
/// GitHub Actions pipeline.
class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key});

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  // Fraction of the available space given to the editor (0.0–1.0).
  double _splitFraction = 0.55;
  bool _stackedLayout = false; // toggled on narrow screens

  @override
  Widget build(BuildContext context) {
    final state = context.watch<StudioState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Code Studio'),
        actions: [
          IconButton(
            tooltip: _stackedLayout ? 'Side-by-side layout' : 'Stacked layout',
            icon: Icon(_stackedLayout ? Icons.view_column : Icons.view_agenda),
            onPressed: () => setState(() => _stackedLayout = !_stackedLayout),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              icon: state.isBuilding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.build),
              label: Text(state.isBuilding ? 'Building...' : 'Build APK'),
              onPressed: state.isBuilding
                  ? null
                  : () {
                      state.resetBuild();
                      showBuildApkSheet(context);
                    },
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = _stackedLayout || constraints.maxWidth < 700;
          return stacked
              ? _buildStacked(context, state, constraints)
              : _buildSideBySide(context, state, constraints);
        },
      ),
    );
  }

  Widget _buildSideBySide(
      BuildContext context, StudioState state, BoxConstraints constraints) {
    final editorWidth = constraints.maxWidth * _splitFraction;
    return Row(
      children: [
        SizedBox(width: editorWidth, child: _editorPanel(state)),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: (details) {
            setState(() {
              _splitFraction = (_splitFraction +
                      details.delta.dx / constraints.maxWidth)
                  .clamp(0.25, 0.8);
            });
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: Container(width: 8, color: Colors.grey.shade300),
          ),
        ),
        Expanded(child: _previewPanel(state)),
      ],
    );
  }

  Widget _buildStacked(
      BuildContext context, StudioState state, BoxConstraints constraints) {
    return Column(
      children: [
        SizedBox(height: constraints.maxHeight * 0.5, child: _editorPanel(state)),
        Container(height: 8, color: Colors.grey.shade300),
        Expanded(child: _previewPanel(state)),
      ],
    );
  }

  Widget _editorPanel(StudioState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('EDITOR', Icons.code, const Color(0xFF1E1E1E), Colors.white70),
        Expanded(child: DartCodeEditor(controller: state.codeController)),
      ],
    );
  }

  Widget _previewPanel(StudioState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader(
            'LIVE PREVIEW', Icons.smartphone, Colors.grey.shade200, Colors.black87),
        Expanded(
          child: Container(
            color: Colors.grey.shade100,
            padding: const EdgeInsets.all(12),
            child: Center(
              child: AspectRatio(
                aspectRatio: 9 / 18,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black26, width: 6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: MiniPreview(source: state.code),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _panelHeader(String label, IconData icon, Color bg, Color fg) {
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: fg, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
        ],
      ),
    );
  }
}
