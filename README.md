# Code Studio (Flutter prototype)

A mobile "code studio" app: write Dart/Flutter code on one side, see a live
preview on the other, and tap **Build APK** to push the code to a GitHub
repo, run a GitHub Actions workflow, and get back a real compiled APK.

## Project layout

```
lib/
  main.dart                     # entry point, Provider wiring
  state/studio_state.dart       # editor content + GitHub config + build pipeline state
  services/github_service.dart  # GitHub REST calls: push file, dispatch, poll, artifact
  widgets/dart_code_editor.dart # syntax-highlighted editor + line numbers
  widgets/mini_preview.dart     # lightweight live-preview renderer
  widgets/build_apk_sheet.dart  # GitHub config form + live build log/result
  screens/studio_screen.dart    # split-view layout, Build APK app bar action
.github/workflows/build_apk.yml # the workflow the app triggers
```

## Running it

```
flutter pub get
flutter run
```

## Setting up the GitHub side

1. Push this repo (or your own) to GitHub with `.github/workflows/build_apk.yml`
   included — it must declare `on: workflow_dispatch`.
2. Create a **fine-grained personal access token** scoped to that one repo,
   with **Contents: Read and write** and **Actions: Read and write**
   permissions.
3. In the app, tap **Build APK** and fill in:
   - Owner/org and repository name
   - Branch (defaults to `main`)
   - Workflow file name (`build_apk.yml`)
   - Path to write the editor's code to (e.g. `lib/main.dart`)
   - The personal access token

Tapping **Push & Build** then:
1. `PUT /repos/{owner}/{repo}/contents/{path}` — commits the editor's code.
2. `POST .../actions/workflows/{workflow}/dispatches` — starts the workflow.
3. Polls `GET .../actions/workflows/{workflow}/runs` to find the new run.
4. Polls `GET .../actions/runs/{run_id}` until `status == completed`.
5. `GET .../actions/runs/{run_id}/artifacts` — returns the APK's download URL.

The token lives only in memory for the running app session; it is never
written into the pushed code or persisted to disk in this prototype. For a
production build, move it into secure storage (e.g. `flutter_secure_storage`)
and consider using a short-lived GitHub App installation token instead of a
personal access token.

## About the "Live Preview" panel

True live rendering of arbitrary Dart source on a phone isn't possible
without embedding a full Dart VM and Flutter engine — that's effectively
what the CI build already does. Instead, `MiniPreview` parses a small,
common subset of widget-construction syntax (`Text`, `Container`, `Column`,
`Row`, `Center`, `Padding`, `Icon`, `ElevatedButton`) directly out of the
`build()` method's `return` statement and renders it as real Flutter
widgets, live, as you type. Code outside that subset shows a clear
"can't preview this" message rather than a wrong guess — use **Build APK**
to see the real, fully-compiled result.

## Extending this prototype

- Swap `MiniPreview` for an embedded DartPad/webview if you want broader
  language coverage at the cost of needing network access and a hosted
  execution backend.
- Add a repo/token picker backed by GitHub OAuth device flow instead of a
  manually pasted PAT.
- Persist multiple files/projects instead of a single in-memory buffer.
- Add push-notification or WebSocket-based run updates instead of polling.
