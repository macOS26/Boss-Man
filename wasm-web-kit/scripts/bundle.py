#!/usr/bin/env python3
"""Generic wasm-web-kit asset bundler for file:/// playability.

Walks a web/ directory and emits web/bundle.js, containing:
  1. window.__BUNDLE__ — { path -> data: URL } for every shipped asset
     (manifest.json, the wasm module, fonts/images/sounds/text from the
     manifest). Each asset is keyed under all the spellings the runtime
     might ask for: full relative path, bare basename, with/without an
     "assets/" prefix.
  2. A fetch() shim that intercepts requests for any bundled path and
     redirects them to the inline data URL. Browsers happily fetch data
     URLs from a file:// origin and honour the embedded MIME type, which
     is what WebAssembly.instantiateStreaming wants for the wasm module.

Usage:
  bundle.py WEB_DIR [WASM_FILENAME] [--asset-root ROOT]

WASM_FILENAME defaults to whichever .wasm file lives at the top of
WEB_DIR. ROOT defaults to WEB_DIR itself; pass --asset-root when the
manifest's paths are relative to a directory other than web/ (e.g.
the C++ port keeps assets at ../assets, matching index.html's
assetRoot setting).

Drop this into a port's build script after the wasm is published into
web/, e.g.:
  python3 ../wasm-web-kit/scripts/bundle.py web boss.wasm

The bundle can be deleted (or its <script> tag removed from index.html)
when shipping behind a real HTTP server.
"""
from __future__ import annotations
import base64, json, pathlib, sys

MIME = {
    ".wasm": "application/wasm",
    ".json": "application/json",
    ".ttf":  "font/ttf",
    ".otf":  "font/otf",
    ".png":  "image/png",
    ".jpg":  "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".wav":  "audio/wav",
    ".mp3":  "audio/mpeg",
    ".ogg":  "audio/ogg",
    ".aiff": "audio/aiff",
}

SHIM = """
(function () {
  // file:/// has no real CORS to break around, so redirect every asset
  // request through the inline data URL. Browsers fetch data URLs from
  // any origin and honour the embedded MIME type, which is what
  // WebAssembly.instantiateStreaming wants for the .wasm.
  const origFetch = window.fetch.bind(window);
  function lookup(url) {
    const u = String(url);
    if (window.__BUNDLE__[u]) return window.__BUNDLE__[u];
    for (const k of Object.keys(window.__BUNDLE__)) {
      if (u === k || u.endsWith('/' + k)) return window.__BUNDLE__[k];
    }
    return null;
  }
  window.fetch = function (input, init) {
    const url = typeof input === 'string' ? input : (input && input.url) || '';
    const hit = lookup(url);
    if (hit) return origFetch(hit, init);
    return origFetch(input, init);
  };
})();
"""

def manifest_paths(manifest: dict) -> list[str]:
    out: list[str] = []
    for key in ("fonts", "images", "sounds", "text", "texts"):
        out.extend(manifest.get(key, []))
    return out

def encode(path: pathlib.Path) -> str:
    mime = MIME.get(path.suffix.lower(), "application/octet-stream")
    b64  = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime};base64,{b64}"

def discover_wasm(web: pathlib.Path) -> str | None:
    matches = sorted(p.name for p in web.glob("*.wasm"))
    return matches[0] if matches else None

def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    # Parse args: WEB_DIR [WASM] [--asset-root ROOT]
    positional: list[str] = []
    asset_root_override: str | None = None
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--asset-root" and i + 1 < len(argv):
            asset_root_override = argv[i + 1]
            i += 2
            continue
        positional.append(a)
        i += 1
    if not positional:
        print(__doc__, file=sys.stderr)
        return 2
    web = pathlib.Path(positional[0]).resolve()
    if not web.is_dir():
        print(f"error: {web} is not a directory", file=sys.stderr)
        return 2
    wasm_name = positional[1] if len(positional) > 1 else discover_wasm(web)
    out = web / "bundle.js"

    # manifest is optional — kit examples sometimes ship none.
    manifest_path = web / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}

    asset_root = (web / asset_root_override).resolve() if asset_root_override else web

    # Asset paths are relative to assetRoot in the runtime. Try assetRoot
    # first, then fall back to web/<path> + web/assets/<path> so any
    # reasonable layout resolves.
    asset_candidates: list[tuple[pathlib.Path, str]] = []
    for raw in manifest_paths(manifest):
        asset_candidates.append((asset_root / raw, raw))           # assetRoot/<raw>
        asset_candidates.append((web / raw, raw))                  # web/<raw>
        asset_candidates.append((web / "assets" / raw, raw))       # web/assets/<raw>

    bare: list[tuple[pathlib.Path, str]] = []
    if manifest_path.exists():
        bare.append((manifest_path, "manifest.json"))
    if wasm_name:
        wasm_path = web / wasm_name
        if wasm_path.exists():
            bare.append((wasm_path, wasm_name))

    entries: dict[str, str] = {}
    used_logical: set[str] = set()
    for abs_path, logical in asset_candidates + bare:
        if not abs_path.exists() or logical in used_logical:
            continue
        url = encode(abs_path)
        used_logical.add(logical)
        # Register under several spellings so any caller hits:
        #   - the manifest path as-is
        #   - that path prefixed with "assets/"
        #   - the bare basename
        entries[logical] = url
        entries["assets/" + logical] = url
        entries[logical.split("/")[-1]] = url

    for raw in manifest_paths(manifest):
        if raw not in entries:
            print(f"warning: bundled asset not found: {raw}", file=sys.stderr)

    body = "window.__BUNDLE__ = " + json.dumps(entries, separators=(",", ":")) + ";\n"
    body += SHIM
    out.write_text(body)
    total = sum(len(v) for v in entries.values())
    print(f"{out}: {len(entries)} entries, {total // 1024} KiB base64 payload")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
