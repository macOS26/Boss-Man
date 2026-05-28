# Hello, SuperBox64 SpriteKit

The smallest possible consumer of the framework — a moving sprite + label —
that exercises the full build path: `swift build → wasm32-wasip1 → runtime.js
→ Canvas2D`.

## Build

```sh
# From this directory
TOOLCHAINS=org.swift.6.3.2-release \
  xcrun --toolchain swift swift build \
  --swift-sdk swift-6.3.2-RELEASE_wasm -c release

# Ship the artifact
cp .build/wasm32-unknown-wasip1/release/Hello.wasm web/hello.wasm
cp ../../../runtime.js                              web/runtime.js
```

## Run

```sh
cd web && python3 -m http.server 8080
# open http://localhost:8080
```

## What it shows

- `SKView.presentScene(_:)` driving the frame loop via `boot`/`frame` exports.
- `SKAction.sequence` + `.repeatForever` + easing.
- Two parallel actions on one node (move + rotate).
- `SKScene.keyDown` handling.
- Linking the bundled Box2D bridge (even though this demo doesn't simulate).
