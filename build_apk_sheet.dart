import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../state/studio_state.dart';

/// Shown when the user taps "Build APK". First collects/edits GitHub
/// config (owner/repo/token/branch/workflow file) if incomplete, then
/// shows a live log of the push -> dispatch -> poll -> artifact pipeline.
Future<void> showBuildApkSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _BuildApkSheet(),
  );
}

class _BuildApkSheet extends StatefulWidget {
  const _BuildApkSheet();

  @override
  State<_BuildApkSheet> createState() => _BuildApkSheetState();
}

class _BuildApkSheetState extends State<_BuildApkSheet> {
  late final TextEditingController _owner;
  late final TextEditingController _repo;
  late final TextEditingController _token;
  late final TextEditingController _branch;
  late final TextEditingController _workflow;
  late final TextEditingController _path;

  @override
  void initState() {
    super.initState();
    final cfg = context.read<StudioState>().githubConfig;
    _owner = TextEditingController(text: cfg.owner);
    _repo = TextEditingController(text: cfg.repo);
    _token = TextEditingController(text: cfg.token);
    _branch = TextEditingController(text: cfg.branch);
    _workflow = TextEditingController(text: cfg.workflowFileName);
    _path = TextEditingController(text: cfg.codeFilePath);
  }

  void _saveConfig(StudioState state) {
    state.githubConfig
      ..owner = _owner.text.trim()
      ..repo = _repo.text.trim()
      ..token = _token.text.trim()
      ..branch = _branch.text.trim().isEmpty ? 'main' : _branch.text.trim()
      ..workflowFileName =
          _workflow.text.trim().isEmpty ? 'build_apk.yml' : _workflow.text.trim()
      ..codeFilePath =
          _path.text.trim().isEmpty ? 'lib/main.dart' : _path.text.trim();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<StudioState>();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Build APK via GitHub Actions',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text(
              'Pushes your code to a repo, runs a build workflow, and '
              'returns the compiled artifact.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            if (!state.isBuilding) ...[
              _field('Owner / org', _owner, hint: 'e.g. octocat'),
              _field('Repository', _repo, hint: 'e.g. my-flutter-app'),
              _field('Branch', _branch, hint: 'main'),
              _field('Workflow file', _workflow, hint: 'build_apk.yml'),
              _field('Path to write code', _path, hint: 'lib/main.dart'),
              _field('Personal access token', _token,
                  hint: 'repo + workflow scopes', obscure: true),
              const SizedBox(height: 8),
              const Text(
                'The token is kept only in memory for this session — it is '
                'never written into the pushed code or stored on disk.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.rocket_launch),
                  label: const Text('Push & Build'),
                  onPressed: () {
                    _saveConfig(state);
                    state.buildApk();
                  },
                ),
              ),
            ] else ...[
              _buildProgress(state),
            ],
            if (state.logs.isNotEmpty && !state.isBuilding) ...[
              const SizedBox(height: 16),
              _buildResult(context, state),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController controller,
      {String? hint, bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildProgress(StudioState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(_stageLabel(state.stage)),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: state.logs
                .map((l) => Text(l,
                    style: const TextStyle(
                        color: Colors.greenAccent,
                        fontFamily: 'monospace',
                        fontSize: 12)))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildResult(BuildContext context, StudioState state) {
    if (state.stage == BuildStage.success && state.downloadUrl != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Build succeeded'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Open artifact download'),
              onPressed: () => launchUrl(Uri.parse(state.downloadUrl!),
                  mode: LaunchMode.externalApplication),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Note: GitHub artifact URLs require the same auth token to '
            'download — opening this link in a browser you are not '
            'signed into may prompt for authentication.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      );
    }
    if (state.stage == BuildStage.failed) {
      return Row(
        children: [
          const Icon(Icons.error, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text(state.errorMessage ?? 'Build failed')),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  String _stageLabel(BuildStage stage) {
    switch (stage) {
      case BuildStage.pushingCode:
        return 'Pushing code to GitHub...';
      case BuildStage.triggeringWorkflow:
        return 'Triggering GitHub Actions workflow...';
      case BuildStage.waitingForRun:
        return 'Waiting for the run to start...';
      case BuildStage.running:
        return 'Build running on GitHub Actions...';
      case BuildStage.fetchingArtifact:
        return 'Fetching build artifact...';
      default:
        return 'Working...';
    }
  }
}
