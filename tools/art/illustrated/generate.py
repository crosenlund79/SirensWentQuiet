"""Regenerate every Version C template PNG into assets/graphics/illustrated/.

    python3 tools/art/illustrated/generate.py            # everything (about 3 minutes)
    python3 tools/art/illustrated/generate.py walls      # one module: floors, walls, tokens, furniture

Then reimport in Godot (godot --headless --path . --import). New PNGs need
mipmaps/generate=true in their .import file (the camera zooms out to ~0.4
screen px per texel). Output is deterministic: noise is seeded from names.
"""
from __future__ import annotations

import sys

import floors
import furniture
import tokens
import walls

MODULES = {"floors": floors, "walls": walls, "tokens": tokens, "furniture": furniture}

if __name__ == "__main__":
    for name in (sys.argv[1:] or list(MODULES)):
        MODULES[name].build_all()
