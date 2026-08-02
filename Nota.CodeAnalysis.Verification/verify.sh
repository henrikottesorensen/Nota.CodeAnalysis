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
#    IDE0005 unused using directive          the one CS8019 was supposed to cover
#    IDE0008  var instead of an explicit type
#    UA1000   using directives out of order   UsingLayoutAnalyser
#    SA1208   System usings not placed first
#    SA1516   no blank line after the System group
expected=(IDE0005 IDE0008 UA1000 SA1208 SA1516)

# VerifyRules is what pulls Samples/ into the compilation. Without it the project builds empty, which
# is what every other build of this solution wants.
output="$(dotnet build "$here/Nota.CodeAnalysis.Verification.csproj" \
    --no-incremental -v:m -p:VerifyRules=true -p:TreatWarningsAsErrors=false 2>&1 || true)"

for rule in "${expected[@]}"; do
    if ! grep -qE "(warning|error) $rule[:(]" <<<"$output"; then
        failures+=("$rule did not report - it is configured but not reaching consumers")
    fi
done

if [ ${#failures[@]} -ne 0 ]; then
    printf 'Verification failed:\n' >&2
    printf '  - %s\n' "${failures[@]}" >&2
    printf '\nFull build output:\n%s\n' "$output" >&2
    exit 1
fi

printf 'All %d rules reported.\n' "${#expected[@]}"
