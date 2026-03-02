# Contributing to Giggy

Thanks for your interest in helping! This project is a handcrafted ECS + game in Zig. The focus is clarity, explicitness, and gameplay feel.

## Quick start

1) Install Zig (recent stable version - currently `0.15.2`).
2) Install raylib, or build it locally as described in `README.md`.
3) Build and run:

```bash
zig build run
```

Example targets:

```bash
zig build example-blob
zig build run-example-blob
zig build examples
```

## What to work on

If you are unsure where to help, pick something that aligns with the roadmap (`ROADMAP.md`). 

## Code conventions

- Prefer explicit APIs and clear data flow.
- Favor readability over abstraction.
- Keep gameplay simulation separate from presentation.
- If possible, add unit tests for bug fixes and new behavior.
- If you touch Zig code, run `zig fmt` on the files you change.

## Tests

- Run engine tests: `zig test src/engine/$MODULE`
- If raylib headers are not in a standard include path, add includes, e.g.:
  - zig test --dep engine -Mengine=src/engine/root.zig -I third_party/raylib/include -I third_party/enet/include -isystem /usr/include/

## Submitting changes

1) Create a focused branch.
2) Keep PRs small and scoped; include a short description of intent and behavior.
3) If behavior changes, note how you tested it (manual steps are fine).

## Bug reports and requests

Open an issue with:

- What you expected vs what happened.
- Steps to reproduce.
- Relevant logs or screenshots.
- Your OS and Zig version.

## License

By contributing, you agree that your contributions are licensed under Apache-2.0.
