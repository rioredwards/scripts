#!/bin/sh
set -eu
root="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/scripts/hooks" "$fixture/bin"
ln -s "$root/hooks/lib" "$fixture/scripts/hooks/lib"
cat > "$fixture/bin/keyfor" <<'KEY'
#!/bin/sh
printf test-key
KEY
cat > "$fixture/bin/curl" <<'CURL'
#!/bin/sh
cat > "$REQUEST_FILE"
[ "${MOCK_TIMEOUT:-}" != 1 ] || exit 28
if [ "${MOCK_REFUSAL:-}" = 1 ]; then
  printf '%s\n200\n' '{"output":[{"type":"message","content":[{"type":"refusal","refusal":"declined"}]}]}'
  exit 0
fi
printf '%s\n200\n' '{"output":[{"type":"message","content":[{"type":"output_text","text":"{\"snippets\":[\"Cedar\",\"LIME-42\",\"First line\\nSecond line\"]}"}]}]}'
CURL
chmod +x "$fixture/bin/keyfor" "$fixture/bin/curl"
export HOME="$fixture" PATH="$fixture/bin:$PATH" REQUEST_FILE="$fixture/request"
printf 'Name: Cedar\nCode: LIME-42\nFirst line\nSecond line\n' | "$root/clipboard-snippets" | jq -e '.snippets == ["Cedar","LIME-42","First line\nSecond line"]' >/dev/null
jq -e '.input == "Name: Cedar\nCode: LIME-42\nFirst line\nSecond line\n"' "$REQUEST_FILE" >/dev/null
jq -e '.model == "gpt-6-luna" and .store == false and .text.format.strict == true and .text.format.schema.properties.snippets.maxItems == 6' "$REQUEST_FILE" >/dev/null
# Existing callers must continue omitting store.
. "$root/hooks/lib/llm-lib.sh"
llm_json gpt-6-luna test fixture '{"snippets":{"type":"array","items":{"type":"string"}}}' >/dev/null
jq -e 'has("store") | not' "$REQUEST_FILE" >/dev/null
printf '' | "$root/clipboard-snippets" | jq -e '.snippets == []' >/dev/null

if printf fixture | MOCK_TIMEOUT=1 "$root/clipboard-snippets" >/dev/null 2>&1; then
  echo "request failure unexpectedly succeeded" >&2; exit 1
fi

if printf fixture | MOCK_REFUSAL=1 "$root/clipboard-snippets" >/dev/null 2>&1; then
  echo "refusal unexpectedly succeeded" >&2; exit 1
fi
