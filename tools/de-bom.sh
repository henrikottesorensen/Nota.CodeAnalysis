#!/usr/bin/env sh
#
# Removes the UTF-8 byte order mark from source files in a repository.
#
# For trees that carried BOMs because SA1412 demanded one. It does not, and never did, do anything
# for the build: a file without a BOM compiles fine, since the compiler assumes UTF-8 when no mark is
# present. What the mark was quietly protecting against is a file saved in the system codepage, and
# that is now the encoding check's job rather than the BOM's.
#
# Usage:
#   de-bom.sh [path]            report what would change, touch nothing
#   de-bom.sh [path] --apply    do it
#
# Reports by default on purpose. This edits every source file in a repository at once, and the first
# thing anyone should see is the list, not the diff.
#
# Refuses to run on a dirty git tree unless --force, so the result is one reviewable commit that
# git checkout can undo.
#
# What it will not touch:
#   - UTF-16 files. Their BOM is the only record of the encoding and removing it destroys the file.
#     svcutil and EF migrations emit these.
#   - .sln files, which some tooling still expects to start with a mark.
#   - bin, obj, .git, node_modules, packages.
#
# POSIX sh, no GNU-isms: runs on macOS and in a Linux container alike. Paths with spaces are handled,
# which matters because "Service References" has one.

set -eu

root="."
apply=0
force=0

for arg in "$@"; do
    case "$arg" in
        --apply) apply=1 ;;
        --force) force=1 ;;
        -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) printf 'unknown option: %s\n' "$arg" >&2; exit 2 ;;
        *) root="$arg" ;;
    esac
done

[ -d "$root" ] || { printf 'not a directory: %s\n' "$root" >&2; exit 2; }

if [ "$apply" -eq 1 ] && [ "$force" -eq 0 ] && git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    if [ -n "$(git -C "$root" status --porcelain 2>/dev/null)" ]; then
        printf 'The tree has uncommitted changes.\n' >&2
        printf 'Commit or stash first, so this lands as one revertible commit - or pass --force.\n' >&2
        exit 1
    fi
fi

# Extensions worth carrying a BOM historically. Widen if a tree needs it; .sln is left out
# deliberately.
found="$(find "$root" \
    \( -name '*.cs' -o -name '*.csproj' -o -name '*.props' -o -name '*.targets' \
       -o -name '*.json' -o -name '*.resx' -o -name '*.config' -o -name '*.xaml' -o -name '*.md' \) \
    -not -path '*/bin/*' -not -path '*/obj/*' -not -path '*/.git/*' \
    -not -path '*/node_modules/*' -not -path '*/packages/*' \
    -exec sh -c '
        for f do
            # Only EF BB BF. FF FE and FE FF are UTF-16 and must keep their mark.
            case "$(head -c 3 "$f" | od -An -tx1 | tr -d " \n")" in
                efbbbf) printf "%s\n" "$f" ;;
            esac
        done
    ' sh {} +)"

if [ -z "$found" ]; then
    printf 'No UTF-8 byte order marks found under %s\n' "$root"
    exit 0
fi

count="$(printf '%s\n' "$found" | wc -l | tr -d ' ')"

if [ "$apply" -eq 0 ]; then
    printf '%s\n' "$found" | sed 's|^|  |'
    printf '\n%s file(s) would have their byte order mark removed.\n' "$count"
    printf 'Nothing has been changed. Re-run with --apply.\n'
    exit 0
fi

printf '%s\n' "$found" | while IFS= read -r f; do
    # Write back into the original rather than moving a temp over it, so the inode, the permissions
    # and anything watching the file survive.
    tail -c +4 "$f" > "$f.debom" && cat "$f.debom" > "$f" && rm -f "$f.debom"
done

printf '%s file(s) de-BOMed under %s\n' "$count" "$root"
printf 'Review with git diff - every change should be one line, the first one.\n'
