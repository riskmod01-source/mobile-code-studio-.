import 'dart:convert';
import 'package:http/http.dart' as http;
import '../state/studio_state.dart';

/// Thin wrapper around the GitHub REST API for the specific calls the
/// studio needs: push a file, dispatch a workflow, watch a run, grab an
/// artifact link. Kept dependency-free (just `http`) so it's easy to audit.
class GitHubService {
  static const _base = 'https://api.github.com';

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  /// Creates or updates a file in the repo via the Contents API.
  /// GitHub requires the current file's `sha` when updating an existing
  /// file, so we look that up first (a 404 just means "new file").
  Future<void> pushFile({
    required GitHubConfig config,
    required String content,
    required String commitMessage,
  }) async {
    final path = config.codeFilePath;
    final uri = Uri.parse(
      '$_base/repos/${config.owner}/${config.repo}/contents/$path',
    );

    String? existingSha;
    final existing = await http.get(
      uri.replace(queryParameters: {'ref': config.branch}),
      headers: _headers(config.token),
    );
    if (existing.statusCode == 200) {
      existingSha = jsonDecode(existing.body)['sha'] as String?;
    } else if (existing.statusCode != 404) {
      throw Exception(
        'Failed to check existing file (${existing.statusCode}): ${existing.body}',
      );
    }

    final body = {
      'message': commitMessage,
      'content': base64Encode(utf8.encode(content)),
      'branch': config.branch,
      if (existingSha != null) 'sha': existingSha,
    };

    final response = await http.put(
      uri,
      headers: _headers(config.token),
      body: jsonEncode(body),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Failed to push file (${response.statusCode}): ${response.body}',
      );
    }
  }

  /// Fires a `workflow_dispatch` event for the configured workflow file.
  /// The target workflow's YAML must declare `on: workflow_dispatch`.
  Future<void> triggerWorkflow({required GitHubConfig config}) async {
    final uri = Uri.parse(
      '$_base/repos/${config.owner}/${config.repo}/actions/workflows/'
      '${config.workflowFileName}/dispatches',
    );

    final response = await http.post(
      uri,
      headers: _headers(config.token),
      body: jsonEncode({'ref': config.branch}),
    );

    if (response.statusCode != 204) {
      throw Exception(
        'Failed to trigger workflow (${response.statusCode}): ${response.body}',
      );
    }
  }

  /// Workflow dispatch doesn't return a run ID directly, so we poll the
  /// workflow's run list and pick the newest run created after we
  /// triggered it.
  Future<int> findRunTriggeredAfter({
    required GitHubConfig config,
    required DateTime after,
    void Function()? onWaiting,
    Duration pollInterval = const Duration(seconds: 3),
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final uri = Uri.parse(
      '$_base/repos/${config.owner}/${config.repo}/actions/workflows/'
      '${config.workflowFileName}/runs?branch=${config.branch}&per_page=5',
    );

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final response = await http.get(uri, headers: _headers(config.token));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final runs = (data['workflow_runs'] as List?) ?? [];
        for (final run in runs) {
          final createdAt = DateTime.parse(run['created_at'] as String);
          if (createdAt.isAfter(after.subtract(const Duration(seconds: 5)))) {
            return run['id'] as int;
          }
        }
      }
      onWaiting?.call();
      await Future.delayed(pollInterval);
    }
    throw Exception('Timed out waiting for the workflow run to start.');
  }

  /// Polls a run's status until GitHub reports it as completed, returning
  /// the final conclusion ("success", "failure", "cancelled", etc.).
  Future<String> pollRunUntilComplete({
    required GitHubConfig config,
    required int runId,
    void Function(String status)? onStatus,
    Duration pollInterval = const Duration(seconds: 5),
    Duration timeout = const Duration(minutes: 15),
  }) async {
    final uri = Uri.parse(
      '$_base/repos/${config.owner}/${config.repo}/actions/runs/$runId',
    );

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final response = await http.get(uri, headers: _headers(config.token));
      if (response.statusCode != 200) {
        throw Exception(
          'Failed to fetch run status (${response.statusCode}): ${response.body}',
        );
      }
      final data = jsonDecode(response.body);
      final status = data['status'] as String; // queued/in_progress/completed
      onStatus?.call(status);
      if (status == 'completed') {
        return data['conclusion'] as String? ?? 'unknown';
      }
      await Future.delayed(pollInterval);
    }
    throw Exception('Timed out waiting for the build to finish.');
  }

  /// Returns the (auth-required) download URL of the first artifact
  /// attached to the run, or null if none exists. Note: this URL still
  /// needs the same Bearer token to actually download the zip — GitHub's
  /// artifact downloads are not public links.
  Future<String?> getFirstArtifactDownloadUrl({
    required GitHubConfig config,
    required int runId,
  }) async {
    final uri = Uri.parse(
      '$_base/repos/${config.owner}/${config.repo}/actions/runs/$runId/artifacts',
    );
    final response = await http.get(uri, headers: _headers(config.token));
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to list artifacts (${response.statusCode}): ${response.body}',
      );
    }
    final data = jsonDecode(response.body);
    final artifacts = (data['artifacts'] as List?) ?? [];
    if (artifacts.isEmpty) return null;
    return artifacts.first['archive_download_url'] as String?;
  }
}
