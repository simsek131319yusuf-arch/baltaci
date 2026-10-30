#!/bin/bash
# g.sh <ref|-> "<prompt>" <out.png>   (run from art/tools)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/tools"
if [ "$1" = "-" ]; then OUT=$(timeout 200 node pipsy.cjs "$2" </dev/null); else OUT=$(timeout 240 node genref.cjs "$ROOT/raw/$1" "$2" </dev/null); fi
echo "$OUT" | tail -2
ID=$(echo "$OUT" | grep '^CHAT' | awk '{print $2}')
[ -z "$ID" ] && exit 1
sleep 20
timeout 90 node "$ROOT/tools/gemget.cjs" "$ID" "$ROOT/raw/$3" </dev/null
echo "$3 | $1 | $2" >> "$ROOT/prompts/promptlar.md"
