# sks2json

macOS CLI that loads `.sks` scene/particle files through real SpriteKit and
emits portable JSON the SuperBox64 SpriteKit runtime can load at start time.

## Why it exists

Apple's `.sks` files are binary plists serialized by SpriteKit's
`NSKeyedUnarchiver`. There's no decoder for them outside Apple platforms, so
we can't read them at runtime on wasm. The pragmatic compromise: convert
once on macOS, ship the resulting `.json` alongside the wasm.

## Build

```sh
cd superbox64-wasmkit/spritekit/Tools/sks2json
swift build -c release
ln -sf "$PWD/.build/release/sks2json" /usr/local/bin/sks2json     # optional
```

## Run

```sh
# Convert one file
sks2json GameScene.sks

# Convert into a dedicated dir
sks2json --out web/scenes GameScene.sks GameMenu.sks

# Walk the current directory for every .sks
sks2json
```

Each `Foo.sks` produces `Foo.json` next to it (or under `--out` if given).

## Runtime side

At game start:

```swift
import SpriteKit
let scene = SKScene(fileNamed: "GameScene")    // routes through SKSceneLoader
let emitter = SKSceneLoader.loadEmitter(fileNamed: "Burst")
```

Behind the scenes, the loader calls the kit's `asset_text` ABI to read
`GameScene.json` (or `GameScene.sks.json`), parses it with `MiniJSON`, and
rebuilds the node tree.

## Supported node kinds

`SKScene`, `SKNode`, `SKSpriteNode`, `SKShapeNode`, `SKLabelNode`,
`SKEmitterNode`, `SKReferenceNode`, `SKCameraNode`.

## JSON schema sample

```json
{
  "kind": "SKScene",
  "size": [1184, 666],
  "backgroundColor": [1.0, 0.93, 0.34, 1.0],
  "children": [
    {
      "kind": "SKSpriteNode",
      "name": "stapler",
      "position": [592, 358],
      "size": [128, 128],
      "anchorPoint": [0.5, 0.5],
      "color": [1, 1, 1, 1],
      "colorBlendFactor": 0,
      "texture": "red-stapler"
    },
    {
      "kind": "SKLabelNode",
      "name": "title",
      "position": [592, 100],
      "text": "BOSS-MAN",
      "fontSize": 96,
      "fontName": "MarkerFelt-Wide",
      "fontColor": [0, 0, 0, 1],
      "horizontalAlignment": "center",
      "verticalAlignment":   "baseline"
    }
  ]
}
```

## Limits

- Scene actions stored in the `.sks` (drag-into-node Action editor) aren't
  encoded yet — Apple's `SKAction` doesn't round-trip cleanly. Add them in
  code instead.
- Physics body shapes other than rect/circle aren't extracted from .sks
  metadata. Set them in code on the matching named node.
- `SKWarpGeometry`, `SK3DNode`, shaders aren't supported (matches the
  runtime's coverage).
