#!/usr/bin/env bash
# Session knobs and the reply cap, with what each value means. Logic and the
# mid-session re-inject live in ../knobs.sh.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/knobs.sh"
