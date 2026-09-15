import 'package:flutter/material.dart';

void main() {
  runApp(const CodeStudioApp());
}

class CodeStudioApp extends StatelessWidget {
  const CodeStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A1020),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF55D6BE),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Inter',
      ),
      home: const CodeStudioScreen(),
    );
  }
}

class CodeStudioScreen extends StatefulWidget {
  const CodeStudioScreen({super.key});

  @override
  State<CodeStudioScreen> createState() => _CodeStudioScreenState();
}

class _CodeStudioScreenState extends State<CodeStudioScreen> {
  final TextEditingController _codeController = TextEditingController(
    text: '''import 'package:flutter/material.dart';

void main() => runApp(const StudioApp());

class StudioApp extends StatelessWidget {
  const StudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Hello from Studio'),
        ),
      ),
    );
  }
}''',
  );

  final CodeStudioController _studioController = CodeStudioController();

  @override
  void dispose() {
    _codeController.dispose();
    _studioController.dispose();
    super.dispose();
  }

  Future<void> _buildApk() async {
    await _studioController.startBuild(
      source: _codeController.text,
      repository: const GithubRepository(
        owner: 'your-handle',
        name: 'flutter-lab',
        branch: 'main',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _studioController,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Mobile Code Studio'),
            actions: [
              BuildStatusPill(status: _studioController.status),
              const SizedBox(width: 16),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 920;
              final editor = CodeEditorPanel(controller: _codeController);
              final preview = const LivePreviewPanel();

              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ProjectHeader(
                      repository: _studioController.repository,
                      onBuild: _buildApk,
                      isBuilding: _studioController.isBuilding,
                    ),
                    const SizedBox(height: 16),
                    isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: editor),
                              const SizedBox(width: 16),
                              Expanded(child: preview),
                            ],
                          )
                        : Column(
                            children: [
                              editor,
                              const SizedBox(height: 16),
                              preview,
                            ],
                          ),
                    if (_studioController.artifactUrl != null) ...[
                      const SizedBox(height: 16),
                      ArtifactDownloadCard(
                        url: _studioController.artifactUrl!,
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class CodeStudioController extends ChangeNotifier {
  BuildStatus status = BuildStatus.ready;
  String? artifactUrl;
  GithubRepository repository = const GithubRepository(
    owner: 'your-handle',
    name: 'flutter-lab',
    branch: 'main',
  );

  bool get isBuilding =>
      status == BuildStatus.preparing || status == BuildStatus.building;

  Future<void> startBuild({
    required String source,
    required GithubRepository repository,
  }) async {
    this.repository = repository;
    artifactUrl = null;
    status = BuildStatus.preparing;
    notifyListeners();

    // Replace this delay with your authenticated app-server request:
    // POST /api/github/build { owner, repo, branch, code }.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    status = BuildStatus.building;
    notifyListeners();

    // Poll GET /api/github/build-status until status == "completed".
    await Future<void>.delayed(const Duration(seconds: 2));
    status = BuildStatus.ready;
    notifyListeners();
  }
}

enum BuildStatus { ready, preparing, building, failed }

class GithubRepository {
  const GithubRepository({
    required this.owner,
    required this.name,
    required this.branch,
  });

  final String owner;
  final String name;
  final String branch;
}

class CodeEditorPanel extends StatelessWidget {
  const CodeEditorPanel({required this.controller, super.key});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ListTile(
            leading: Icon(Icons.description_outlined),
            title: Text('main.dart'),
            subtitle: Text('Dart / Flutter'),
          ),
          SizedBox(
            height: 420,
            child: TextField(
              controller: controller,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.55,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LivePreviewPanel extends StatelessWidget {
  const LivePreviewPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.phone_android_outlined),
                title: Text('Live preview'),
                subtitle: Text('Render the current Dart surface'),
              ),
            ),
            Container(
              height: 420,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF121B2C),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.code_rounded, color: Color(0xFF55D6BE), size: 40),
                  SizedBox(height: 18),
                  Text(
                    'Hello from Studio',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 8),
                  Text('Your Flutter interface is rendering live.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BuildStatusPill extends StatelessWidget {
  const BuildStatusPill({required this.status, super.key});

  final BuildStatus status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      BuildStatus.ready => 'Ready',
      BuildStatus.preparing => 'Preparing',
      BuildStatus.building => 'Building',
      BuildStatus.failed => 'Needs attention',
    };
    return Chip(
      avatar: const CircleAvatar(
        radius: 4,
        backgroundColor: Color(0xFF55D6BE),
      ),
      label: Text(label),
    );
  }
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({
    required this.repository,
    required this.onBuild,
    required this.isBuilding,
  });

  final GithubRepository repository;
  final VoidCallback onBuild;
  final bool isBuilding;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Untitled Flutter project',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text('${repository.owner}/${repository.name} · ${repository.branch}'),
          ],
        ),
        FilledButton.icon(
          onPressed: isBuilding ? null : onBuild,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(isBuilding ? 'Building' : 'Build APK'),
        ),
      ],
    );
  }
}

class ArtifactDownloadCard extends StatelessWidget {
  const ArtifactDownloadCard({required this.url, super.key});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.download_rounded),
        title: const Text('APK build complete'),
        subtitle: Text(url),
        trailing: const Icon(Icons.open_in_new_rounded),
      ),
    );
  }
}