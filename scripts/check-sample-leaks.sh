#!/usr/bin/env bash
# check-sample-leaks.sh, fail if demo SampleData can reach a REAL user's render path.
#
# Every "why is my data dummy" bug this project hit (Overview hero, the widget, the Calories steps,
# Insights/Compare/Explore) was the SAME anti-pattern: a feature view returning `SampleData.…`
# behind a bare `#if DEBUG` (or with no `usesSampleData` gate), so a DEBUG/sim build, and anything
# a tester runs before noticing, showed fabricated numbers as the user's own.
#
# The rule (restate the user's OWN data): in Sources/Features, `SampleData` may appear ONLY
#   (a) inside a `usesSampleData` / `isSampleData` branch (the demo container is opt-in), or
#   (b) inside a `#Preview` block (Xcode canvas only, never shipped).
# A `SampleData` reference inside a `#if DEBUG` region that is NOT a `#Preview` is the banned leak.
#
# Heuristic but precise for the pattern that actually recurred. Runs in CI (safety.yml) and locally.
set -euo pipefail
cd "$(dirname "$0")/.."

# Walk every feature file tracking #if DEBUG / #Preview / #endif nesting; emit a line for each
# SampleData reference inside a `#if DEBUG` block that is not a `#Preview`.
findings="$(
    find Sources/Features -name '*.swift' -print0 | while IFS= read -r -d '' file; do
        awk -v f="$file" '
            /^[[:space:]]*#if[[:space:]]+DEBUG/ { depth++; debug[depth]=1; preview[depth]=0; next }
            /^[[:space:]]*#if/                  { depth++; debug[depth]=0; preview[depth]=0; next }
            /#Preview/                          { if (depth>0) preview[depth]=1 }
            /^[[:space:]]*#endif/               { if (depth>0) depth-- ; next }
            /SampleData/ {
                for (d=1; d<=depth; d++) {
                    if (debug[d] && !preview[d]) {
                        printf "%s:%d: SampleData inside a non-Preview #if DEBUG block (demo data can reach a real render path)\n", f, NR
                        break
                    }
                }
            }
        ' "$file"
    done
)"

if [ -n "$findings" ]; then
    echo "$findings"
    echo ""
    echo "✗ Demo SampleData may leak into a real user's view (see above)."
    echo "  Gate it behind \`if usesSampleData { … }\`, or move it into a \`#Preview\` block."
    exit 1
fi
echo "✓ No SampleData leaks in Sources/Features render paths."
