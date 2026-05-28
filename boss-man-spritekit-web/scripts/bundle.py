#!/usr/bin/env python3
"""Bundle every asset bossman-web ships so the game can run from file:///.

Output: web/bundle.js, which:
  1. Defines window.__BUNDLE__ — a map of asset path -> data: URL.
  2. Wraps window.fetch so requests for any bundled path get redirected
     to the inline data URL. Browsers happily fetch data URLs from a
     file:// origin, so the runtime gets its assets without a server.

Re-run this script whenever assets or bossman.wasm change.
"""
from __future__ import annotations
import base64, json, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WEB  = ROOT / "web"
OUT  = WEB  / "bundle.js"

# (path-relative-to-web, mime-type)
MIME = {
    ".wasm": "application/wasm",
    ".json": "application/json",
    ".ttf":  "font/ttf",
    ".otf":  "font/otf",
    ".png":  "image/png",
    ".jpg":  "image/jpeg",
    ".wav":  "audio/wav",
    ".mp3":  "audio/mpeg",
    ".aiff": "audio/aiff",
}

def manifest_paths(manifest: dict) -> list[str]:
    out = []
    out.extend(manifest.get("fonts", []))
    out.extend(manifest.get("images", []))
    out.extend(manifest.get("sounds", []))
    out.extend(manifest.get("text",   []))
    return out

def encode(path: pathlib.Path) -> str:
    mime = MIME.get(path.suffix.lower(), "application/octet-stream")
    b64  = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime};base64,{b64}"

def main() -> int:
    manifest = json.loads((WEB / "manifest.json").read_text())
    # Manifest paths in this project are relative to web/assets/ (the
    # runtime's ASSET_ROOT). bossman.wasm + manifest.json live in web/.
    asset_files = [("assets/" + p, p) for p in manifest_paths(manifest)]
    bare_files  = [("manifest.json", "manifest.json"),
                   ("bossman.wasm",  "bossman.wasm")]

    entries: dict[str, str] = {}
    for rel_to_web, _logical in asset_files + bare_files:
        p = WEB / rel_to_web
        if not p.exists():
            print(f"warning: missing {rel_to_web}", file=sys.stderr)
            continue
        url = encode(p)
        # The runtime fetches via three flavours of path; register all of
        # them so any caller spelling resolves through the shim:
        #   - "manifest.json"               (discoverAssets, relative)
        #   - "assets/fonts/foo.ttf"        (ASSET_ROOT-prefixed)
        #   - "fonts/foo.ttf"               (raw manifest entry)
        #   - "foo.ttf"                     (basename — runtime never asks
        #                                    for this directly but cheap)
        entries[rel_to_web] = url
        base = rel_to_web.split("/")[-1]
        entries[base] = url
        if rel_to_web.startswith("assets/"):
            entries[rel_to_web[len("assets/"):]] = url

    body = "window.__BUNDLE__ = " + json.dumps(entries, separators=(",", ":")) + ";\n"
    body += """
(function () {
  // file:/// has no real CORS to break around, so just redirect every
  // asset request through the inline data URL. Browsers fetch data URLs
  // happily from any origin and honour the embedded MIME type, which is
  // what WebAssembly.instantiateStreaming wants for .wasm.
  const origFetch = window.fetch.bind(window);
  function lookup(url) {
    const u = String(url);
    if (window.__BUNDLE__[u]) return window.__BUNDLE__[u];
    // file:/// URLs land here as absolute paths; match by suffix.
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
    OUT.write_text(body)
    total = sum(len(v) for v in entries.values())
    print(f"bundle.js: {len(entries)} entries, {total // 1024} KiB base64 payload")
    return 0

if __name__ == "__main__":
    sys.exit(main())
