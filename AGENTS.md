# Repository Guidelines

## Project Structure

Snowy Evening is a Godot game with a Cloudflare co-op backend and a download site. `project.godot` starts at `scenes/startup.tscn`. Gameplay scenes live in `scenes/`, GDScript and shaders in `scripts/`, and models, audio, and game data in `assets/`. The co-op Worker and Durable Object code lives in `server/src/`, with tests in `server/test/`. The static download site lives in `site/` and is published to GitHub Pages.

## Build and Run

Use Godot 4.7.2 with the Mobile renderer. Run these commands from the project root.

- `godot --path .` launches the game.
- `godot --headless --path . --import` imports assets and generates Godot metadata.
- After every change, run `sh tools/build.sh` before reporting the work complete. It rebuilds the macOS and Windows releases, verifies the macOS bundle signature, and refreshes both ZIP archives in `build/upload/`.
- Run `npm ci` in `server/` to install dependencies. There, `npm run dev` starts the local Worker and `npm run typecheck` checks TypeScript.
- `python3 -m http.server -d site` previews the download site. A push to `main` runs `.github/workflows/release.yml`: it builds both platforms, publishes the archives as a new GitHub release, and deploys `site/` to Pages with a generated `builds.json`.

## Coding Style

Use tabs and `snake_case` for GDScript files, functions, and variables. Use PascalCase for named classes. Follow existing TypeScript indentation and naming in the file you edit. Commit Godot-generated `.uid` files alongside new scripts. Include new runtime JSON read through `FileAccess` in both export presets.

## Testing

After importing, run `godot --headless --path . --quit-after 120 scenes/main.tscn` and check for script and parse errors. Play through the changed interaction in the game.

In `server/`, `npm test` runs the Node Durak tests in `test/durak.test.mjs`. For protocol changes, update `server/README.md` and `test/smoke.mjs`. Start the Worker with `npm run dev -- --port 8799` and run `npm run smoke -- http://127.0.0.1:8799` in another terminal.

## Commits and Pull Requests

Use short, imperative subjects with the prefixes seen in history, such as `feat:`, `perf:`, and `chore:`. Summarize the change and verification in the PR, link related issues when available, and attach screenshots or a clip for visible gameplay changes.
