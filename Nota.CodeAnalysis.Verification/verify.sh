#!/usr/bin/env bash
#
# Asserts that the rules this package ships actually report.
#
# The product of this repository is configuration, and configuration fails silently. CS8019 sat in
# the globalconfig asking for unused usings to be reported, and reported nothing, for as long as
# anyone can tell - because a package that ships settings has nothing that exercises them. This is
# the thing that would have said so on the first build.
#
# Run from anywhere. Exits non-zero with the missing rules named.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
props="$here/../Nota.CodeAnalysis/build/Nota.CodeAnalysis.props"

failures=()

# 1. The verification project stands in for a consumer, so the properties it sets itself have to be
#    the ones the props file gives a consumer. If they drift, this project proves nothing about what
#    anyone actually gets.
for property in EnforceCodeStyleInBuild EnableNETAnalyzers GenerateDocumentationFile ImplicitUsings; do
    if ! grep -q "<$property>" "$props"; then
        failures+=("build/Nota.CodeAnalysis.props no longer sets $property, which this project assumes")
    fi
done

# 2. Broken.cs breaks each of these on purpose. A rule that stops reporting is a rule that has been
#    switched off, renamed, or - as with CS8019 - never worked.
#
#    IDE0005   unused using directive          the one CS8019 was supposed to cover
#    IDE0008   var instead of an explicit type
#    UA1000    using directives out of order   UsingLayoutAnalyser
#    UA1001    no blank line between using blocks - see Samples/Unseparated.cs. SA1516 used to cover
#              this, but only because dotnet_separate_import_directive_groups was set, and that key
#              had to go: at any value it arms dotnet format's organize-imports stage, which sorts
#              first party above the vendors and leaves --verify-no-changes failing permanently
#    SA1208    System usings not placed first
#    SA1516    no blank line between members - its own job, not the using one it lost
#    NOTA0001  a source file that is not valid UTF-8, from build/Nota.CodeAnalysis.targets - one of
#              two rules here logged by an MSBuild task rather than an analyser, and so the only ones
#              that cannot be confirmed by reading a severity out of the globalconfig
#    NOTA0002  a source file carrying a UTF-8 byte order mark - Samples/BomMarked.cs. Also from the
#              targets, and the reason the samples are exempt from verify-encoding.sh. A warning
#              where NOTA0001 is an error, which is why the grep below accepts either
#    NOTA0003  an operator leading a wrapped line - see Samples/LeadingOperator.cs. From this
#              repository's own analyser, so it also proves the analyser project loads at all
expected=(IDE0005 IDE0008 UA1000 UA1001 SA1208 SA1516 NOTA0001 NOTA0002 NOTA0003)

# VerifyRules is what pulls Samples/ into the compilation. Without it the project builds empty, which
# is what every other build of this solution wants.
output="$(dotnet build "$here/Nota.CodeAnalysis.Verification.csproj" \
    --no-incremental -v:m -p:VerifyRules=true -p:TreatWarningsAsErrors=false 2>&1 || true)"

for rule in "${expected[@]}"; do
    if ! grep -qE "(warning|error) $rule[:(]" <<<"$output"; then
        failures+=("$rule did not report - it is configured but not reaching consumers")
    fi
done

# 3. Samples/LeadingOperator.cs wraps the same expression both ways. The leading operator is the one
#    NOTA0003 reports; the trailing one is what its fix produces, and nothing may report that - not
#    NOTA0003, and not a StyleCop or formatting rule wanting the operator back where it was. A rule
#    whose fix another rule reports is a loop, not a convention.
leading="$(grep 'LeadingOperator\.cs(' <<<"$output" | sed 's/ \[.*//' | sort -u || true)"
unexpected="$(grep -v 'LeadingOperator\.cs(19,13): warning NOTA0003:' <<<"$leading" || true)"

if [ -n "$unexpected" ]; then
    failures+=("Samples/LeadingOperator.cs reported more than the one leading operator:"$'\n'"$unexpected")
fi

if [ ${#failures[@]} -ne 0 ]; then
    printf 'Verification failed:\n' >&2
    printf '  - %s\n' "${failures[@]}" >&2
    printf '\nFull build output:\n%s\n' "$output" >&2
    exit 1
fi

printf 'All %d rules reported.\n' "${#expected[@]}"
