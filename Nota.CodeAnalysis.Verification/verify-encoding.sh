#!/usr/bin/env sh
#
# Fails if any source file is neither valid UTF-8 nor a BOM-marked UTF-16 file.
#
# This is the guard that has to exist before SA1412 is switched off. SA1412 required a byte order
# mark, which was never the point - but it was, by accident, the only thing standing between the
# build and a file saved as Windows-1252. Measured: such a file compiles with no warning and no
# error, and the compiler writes U+FFFD replacement characters into the assembly. The corruption is
# silent, it reaches the binary, and no analyser reports it, because by the time an analyser runs the
# text has already been decoded.
#
# No analyser can cover this anyway - it is a property of bytes on disk, and it applies to .json and
# .resx as much as to .cs. Hence a script.
#
# UTF-16 is accepted when it carries a BOM. Generated output - svcutil service references, EF
# migrations - is often UTF-16, the compiler reads it correctly from the BOM, and such a file must
# keep that BOM: it is the only thing recording the encoding.
#
# What this cannot catch: a wrong encoding that happens to produce valid UTF-8 - the classic "â€œ"
# mojibake - which is indistinguishable from someone deliberately writing those characters. What it
# does catch is any file containing a byte sequence that is not legal UTF-8, which is every ordinary
# case of an ANSI file with Danish, Cyrillic or CJK text in it.
#
# POSIX sh and BSD-safe, so it runs on a developer's Mac and in a Linux build container alike.
#
# The verification samples are excluded. They are wrong on purpose - one of them is Windows-1252, so
# that NOTA0001 has something to fire on - and this check exists to find files that are wrong by
# accident.
#
# Paths are passed to a child shell by find rather than through a variable and a for loop. That is
# not fussiness: word splitting on an unquoted expansion breaks every path containing a space, and
# reports each half as unreadable - which looks exactly like a corrupt file, in a whole directory of
# them at once, because "Service References" has a space in it.

set -eu

root="${1:-.}"

found="$(find "$root" \
    \( -name '*.cs' -o -name '*.csproj' -o -name '*.json' -o -name '*.resx' -o -name '*.md' -o -name '*.props' -o -name '*.targets' \) \
    -not -path '*/obj/*' -not -path '*/bin/*' -not -path '*/.git/*' \
    -not -path '*/Nota.CodeAnalysis.Verification/Samples/*' \
    -exec sh -c '
        for f do
            bom=$(head -c 3 "$f" | xxd -p)
            case "$bom" in
                fffe*|feff*) ;;
                *) iconv -f UTF-8 -t UTF-8 "$f" >/dev/null 2>&1 || printf "%s\n" "$f" ;;
            esac
        done
    ' sh {} +)"

if [ -n "$found" ]; then
    printf 'Not valid UTF-8:\n' >&2
    printf '%s\n' "$found" | sed 's/^/  /' >&2
    printf '\nThese compile without complaint and land in the assembly as U+FFFD.\n' >&2
    printf 'Re-save them as UTF-8; check the tool or editor that last wrote them.\n' >&2
    exit 1
fi

printf 'All source files are valid UTF-8 or BOM-marked UTF-16.\n'
