#!/usr/bin/env bash
# Which Mac this session runs on, and where Rio is replying from.
# Same detector as the per-prompt hook, so the two never disagree: ../seat.sh.

set -euo pipefail

exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/seat.sh" --machine
