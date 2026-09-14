import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/github_service.dart';
import '../widgets/dart_code_editor.dart';

/// Lifecycle of a single "Build APK" run.
enum BuildStage {
  idle,
  pushingCode,
  triggeringWorkflow,
  waitingForRun,
  running,
  fetchingArtifact,
  success,
  failed,
}

/// Configuration needed to talk to a GitHub repo + Actions workflow.
/// Kept separate from [StudioState] so it can be persisted/cleared independently.
class GitHubConfig {
  String owner;
  String repo;
  String token;
  String branch;
  String workflowFileName; // e.g. "build_apk.yml"
  String codeFilePath; // where in the repo the editor content is written

  GitHubConfig({
    this.owner = '',
    this.repo = '',
    this.token = '',
    this.branch = 'main',
    this.workflowFileName = 'build_apk.yml',
    this.codeFilePath = 'lib/main.dart',
  });

  bool get isComplete =>
      owner.trim().isNotEmpty &&
      repo.trim().isNotEmpty &&
      token.trim().isNotEmpty &&
      workflowFileName.trim().isNotEmpty;
}

/// Central app state: the code being edited, the GitHub config, and the
/// live status of an in-flight build. Exposed to the widget tree via
/// ChangeNotifierProvider in main.dart.
class StudioState extends ChangeNotifier {
  StudioState() {
    codeController.addListener(() {
      // Keep a plain-string copy in sync for the preview parser / GitHub push.
      _code = codeController.text;
      notifyListeners();
    });
  }

  // ---- Editor content -----------------------------------------------
  final DartSyntaxController codeController = DartSyntaxController(
    text: _defaultSample,
  );
  String _code = _defaultSample;
  String get code => _code;

  // ---- GitHub configuration -------------------------------------------
  final GitHubConfig githubConfig = GitHubConfig();

  // ---- Build pipeline status ------------------------------------------
  BuildStage stage = BuildStage.idle;
  final List<String> logs = [];
  String? downloadUrl;
  String? errorMessage;

  final GitHubService _github = GitHubService();

  bool get isBuilding =>
      stage != BuildStage.idle &&
      stage != BuildStage.success &&
      stage != BuildStage.failed;

  void _log(String message) {
    logs.add(message);
    notifyListeners();
  }

  void resetBuild() {
    stage = BuildStage.idle;
    logs.clear();
    downloadUrl = null;
    errorMessage = null;
    notifyListeners();
  }

  /// Drives the full pipeline:
  /// 1. Push the editor's code to the repo (create-or-update file).
  /// 2. Trigger the GitHub Actions workflow (workflow_dispatch).
  /// 3. Poll for the run that was just triggered.
  /// 4. Poll that run until it finishes.
  /// 5. Fetch the resulting artifact's download URL.
  Future<void> buildApk() async {
    if (!githubConfig.isComplete) {
      errorMessage = 'Please fill in GitHub owner, repo, and token first.';
      notifyListeners();
      return;
    }

    logs.clear();
    downloadUrl = null;
    errorMessage = null;
    final triggeredAfter = DateTime.now().toUtc();

    try {
      stage = BuildStage.pushingCode;
      _log('Pushing ${githubConfig.codeFilePath} to '
          '${githubConfig.owner}/${githubConfig.repo}@${githubConfig.branch}...');
      await _github.pushFile(
        config: githubConfig,
        content: code,
        commitMessage: 'Update ${githubConfig.codeFilePath} from Code Studio',
      );
      _log('Code pushed.');

      stage = BuildStage.triggeringWorkflow;
      _log('Triggering workflow "${githubConfig.workflowFileName}"...');
      await _github.triggerWorkflow(config: githubConfig);
      _log('Workflow dispatch sent.');

      stage = BuildStage.waitingForRun;
      _log('Waiting for the run to appear...');
      final runId = await _github.findRunTriggeredAfter(
        config: githubConfig,
        after: triggeredAfter,
        onWaiting: () => _log('...still looking for the new run'),
      );
      _log('Found run #$runId.');

      stage = BuildStage.running;
      final conclusion = await _github.pollRunUntilComplete(
        config: githubConfig,
        runId: runId,
        onStatus: (status) => _log('Run status: $status'),
      );
      _log('Run finished with conclusion: $conclusion');

      if (conclusion != 'success') {
        throw Exception('Workflow run did not succeed (conclusion: $conclusion).');
      }

      stage = BuildStage.fetchingArtifact;
      _log('Fetching build artifact...');
      final url = await _github.getFirstArtifactDownloadUrl(
        config: githubConfig,
        runId: runId,
      );
      if (url == null) {
        throw Exception('Workflow succeeded but no artifact was found.');
      }
      downloadUrl = url;
      _log('Artifact ready.');
      stage = BuildStage.success;
    } catch (e) {
      errorMessage = e.toString();
      stage = BuildStage.failed;
      _log('Build failed: $e');
    }
    notifyListeners();
  }

  static const String _defaultSample = '''
import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Text('Hello from Code Studio'),
          Padding(
            child: Container(
              color: blue,
              child: Text('Live preview updates as you type'),
            ),
          ),
          ElevatedButton(
            child: Text('Tap me'),
          ),
        ],
      ),
    );
  }
}
''';
}
