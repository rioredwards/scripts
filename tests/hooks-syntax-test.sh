#!/bin/sh
# hooks-syntax-test.sh: syntax-check every script under hooks/ (or the dir given
# as $1). A parse error in any hook file, e.g. lib/hooklog, breaks every hook,
# so this must fail loudly. Interpreter comes from each file's shebang (so
# extensionless files are covered); nothing is written into the repo.
set -u
root="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
dir="${1:-$root/hooks}"
bad=0
n=0

while IFS= read -r f; do
  case "$f" in */__pycache__/* | */.pytest_cache/*) continue ;; esac
  line="$(head -n 1 "$f" 2>/dev/null)"
  case "$f:$line" in
    *.py:* | *:'#!'*python*) kind=python ;;
    *.js:* | *:'#!'*node*) kind=node ;;
    *:'#!'*perl*) kind=perl ;;
    *:'#!'*zsh*) kind=zsh ;;
    *:'#!'*bash*) kind=bash ;;
    *:'#!'*sh*) kind=sh ;;
    *) continue ;;
  esac
  n=$((n + 1))
  case "$kind" in
    python) out="$(python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' "$f" 2>&1)" ;;
    node) out="$(node --check "$f" 2>&1)" ;;
    perl) out="$(perl -c "$f" 2>&1)" ;;
    *) out="$("$kind" -n "$f" 2>&1)" ;;
  esac || {
    bad=$((bad + 1))
    printf 'SYNTAX ERROR (%s): %s\n%s\n' "$kind" "$f" "$out"
  }
done <<LIST
$(find "$dir" -type f ! -name '.DS_Store' | sort)
LIST

[ "$n" -gt 0 ] || { echo "no scripts found under $dir" >&2; exit 1; }
[ "$bad" -eq 0 ] || exit 1
echo "$n hook scripts parse cleanly"
