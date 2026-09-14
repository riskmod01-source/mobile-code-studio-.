import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/studio_state.dart';
import 'screens/studio_screen.dart';

void main() {
  runApp(const CodeStudioApp());
}

/// Root widget. Wires up the single [StudioState] via Provider so both the
/// editor, live preview, and the Build APK sheet can read/mutate it.
class CodeStudioApp extends StatelessWidget {
  const CodeStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => StudioState(),
      child: MaterialApp(
        title: 'Code Studio',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF3B82F6),
          brightness: Brightness.light,
        ),
        home: const StudioScreen(),
      ),
    );
  }
}
