#!/usr/bin/env sh
#
# Asserts that the rules survive being packaged.
#
# verify.sh proves the globalconfig's content: it imports that file directly and declares the
# analyser references itself, standing in for a consumer. That is not the same as being one, and the
# difference has already mattered twice, both times in changes that had not yet merged.
#
#   - UsingLayoutAnalyser was built against a Roslyn newer than the SDK running it. The compiler
#     answered CS9057, a warning, and skipped the analyser. Green build, no rules.
#   - Microsoft.VisualStudio.Threading.Analyzers acquired PrivateAssets during a version bump, which
#     stops a reference reaching consumers. VSTHRD100 kept firing inside this solution, because the
#     verification project references the analyser directly, while no consumer received it at all.
#
# Neither is visible from inside the solution. Both are obvious the moment something installs the
# package and compiles a file that breaks a rule, which is all this does: pack, install from a local
# feed into a throwaway project, and check each rule reported.
#
# It covers the parts verify.sh cannot reach - PackagePath, the build/ props and targets being
# imported at all, and whether a dependency actually flows - and it is the only check that fails when
# a package installs cleanly and does nothing.
#
# POSIX sh and BSD-safe. Needs network on a cold cache, for the throwaway project's own dependencies.

set -eu

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT INT TERM

feed="$work/feed"
app="$work/app"
mkdir -p "$feed" "$app"

# A version nothing can already have. Without this the check silently passes: NuGet extracts a
# package once per version into the global cache, so re-packing 2.2.0 and installing 2.2.0 gets
# whatever 2.2.0 was extracted first - the change under test never reaches the consumer. That is not
# hypothetical; this script gave a clean pass against a regression it was written to catch, until the
# version was made unique.
version="0.0.0-verify.$(date +%Y%m%d%H%M%S)"

printf 'Packing %s...\n' "$version"
dotnet pack "$root/Nota.CodeAnalysis.sln" --configuration Release --output "$feed" -p:Version="$version" >"$work/pack.log" 2>&1 || {
    printf 'pack failed:\n' >&2
    cat "$work/pack.log" >&2
    exit 1
}

package="Nota.CodeAnalysis.$version.nupkg"
[ -f "$feed/$package" ] || { printf 'no package was produced at %s\n' "$feed/$package" >&2; exit 1; }

printf 'Testing %s as a consumer would install it.\n' "$package"

cat > "$app/nuget.config" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="local" value="$feed" />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
</configuration>
EOF

cat > "$app/App.csproj" <<EOF
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <!-- Off, so every rule reports instead of the first one stopping the build. -->
    <TreatWarningsAsErrors>false</TreatWarningsAsErrors>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Nota.CodeAnalysis" Version="$version" />
    <!-- SerilogAnalyzer has nothing to say without Serilog present. -->
    <PackageReference Include="Serilog" Version="4.2.0" />
  </ItemGroup>
</Project>
EOF

# Every line here breaks something on purpose. What is asserted below is that each rule survived
# packaging - not that the rule works, which verify.sh already covers.
cat > "$app/Broken.cs" <<'EOF'
using Nota.Vendor;
using System;

using Serilog;

namespace App;

/// <summary>Breaks one rule per analyser, on purpose.</summary>
public static class Broken
{
    /// <summary>var is IDE0008, from the globalconfig.</summary>
    public static string Value()
    {
        var text = typeof(Thing).Name + Environment.NewLine;

        return text;
    }

    /// <summary>async void is VSTHRD100, from the threading analyser.</summary>
    public static async void Fire()
    {
        await System.Threading.Tasks.Task.Delay(1).ConfigureAwait(false);
    }

    /// <summary>An unbound property is Serilog003, from SerilogAnalyzer.</summary>
    public static void LogIt() => Log.Information("Hello {Name}");
}
EOF

cat > "$app/Vendor.cs" <<'EOF'
namespace Nota.Vendor;

/// <summary>Stub, so the first using resolves.</summary>
public class Thing
{
}
EOF

# Windows-1252, for NOTA0001 - which proves build/Nota.CodeAnalysis.targets was packed and imported.
printf 'namespace App;\n\n/// <summary>Saved in the wrong encoding on purpose.</summary>\npublic static class Mis\n{\n    /// <summary>Danish text.</summary>\n    public const string T = "' > "$app/MisEncoded.cs"
printf '\346\370\345' >> "$app/MisEncoded.cs"
printf '";\n}\n' >> "$app/MisEncoded.cs"

output="$(cd "$app" && dotnet build --no-incremental -v:m 2>&1 || true)"

#   IDE0008    the globalconfig was packed, and the props file turned rule enforcement on
#   NOTA0001   build/Nota.CodeAnalysis.targets was packed and imported
#   SA1208     StyleCop.Analyzers reached the consumer
#   VSTHRD100  Microsoft.VisualStudio.Threading.Analyzers reached the consumer
#   UA1000     UsingLayoutAnalyser reached the consumer, and loaded on this Roslyn
#   Serilog003 SerilogAnalyzer reached the consumer
expected="IDE0008 NOTA0001 SA1208 VSTHRD100 UA1000 Serilog003"

missing=""
for rule in $expected; do
    if ! printf '%s' "$output" | grep -qE "(warning|error) $rule[:( ]"; then
        missing="$missing $rule"
    fi
done

# CS9057 is never acceptable: it means an analyser referenced a newer compiler than the one running,
# and was skipped. It is a warning, so nothing else would fail.
if printf '%s' "$output" | grep -q "CS9057"; then
    missing="$missing CS9057-was-reported(an-analyser-was-skipped)"
fi

if [ -n "$missing" ]; then
    printf '\nThe package does not deliver:%s\n' "$missing" >&2
    printf 'It installed without complaint. That is what this check is for.\n\n' >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

printf 'All rules survive packaging.\n'
