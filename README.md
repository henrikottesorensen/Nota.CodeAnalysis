# Nota.CodeAnalysis

Nota's code style, StyleCop and code analysis rules, as one package. Install it and a project gets
the same rules as every other project here, enforced at build time rather than agreed in a wiki.

## Installing

The package lives on Nota's GitHub Packages feed, so a `NuGet.config` needs the source:

```xml
<add key="notalib" value="https://nuget.pkg.github.com/Notalib/index.json" />
```

Then reference it once per project, or once in a `Directory.Build.props` for a whole solution:

```xml
<PackageReference Include="Nota.CodeAnalysis" Version="2.2.0">
  <PrivateAssets>all</PrivateAssets>
  <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
</PackageReference>
```

`PrivateAssets` matters: without it the rules flow to anything that references your library, and
whether *your* code uses `var` is nobody else's build error.

## What arrives with it

Four properties are switched on, in `build/Nota.CodeAnalysis.props`:

| Property | Why |
|----------|-----|
| `EnforceCodeStyleInBuild` | without it the IDE#### rules never run, whatever their severity says |
| `EnableNETAnalyzers` | the CA#### rules |
| `GenerateDocumentationFile` | load-bearing, and not obviously so: severity is a filter, and this is the switch that produces the diagnostics being filtered. Remove it and `IDE0005` silently stops reporting |
| `ImplicitUsings` | disabled - usings are stated, not inherited |

Four analyser packages come as dependencies: StyleCop.Analyzers, Microsoft.VisualStudio.Threading.Analyzers,
SerilogAnalyzer, and UsingLayoutAnalyser. One more, Nota's own (`NOTA0002`, with its code fix), is
carried inside the package itself, built from `Nota.CodeAnalysis.Analysers`. Around 400 rule
severities are set in `content/Nota.CodeAnalysis.globalconfig`.

## Configuring it

Nothing is required. The one setting most likely to need changing is which namespaces count as
*yours*, for the using layout - it defaults to `Nota`, which is right for almost everything here.

If your code is called something else, say so in your own `.editorconfig`:

```ini
[*.cs]
usinglayout.first_party_prefixes = Contoso, Fabrikam
```

Comma-separated for several roots. Getting it wrong is not fatal - your namespaces are simply sorted
as one more vendor rather than last.

## Rules worth knowing before your first build

Most of this is unsurprising. These are the ones that catch people out:

- **`IDE0008` is an error.** `var` is banned outright; write the type.
- **`VSTHRD100` is an error.** No `async void`.
- **`NOTA0001`** fails the build on a source file that is not valid UTF-8. It is an MSBuild task
  rather than an analyser because it has to see the bytes: a file saved as Windows-1252 compiles with
  no warning at all and reaches the assembly as U+FFFD replacement characters. UTF-16 with a byte
  order mark passes, since the compiler reads it correctly - and such a file must keep its BOM, which
  is the only record of its encoding.
- **`NOTA0002`**: when an expression wraps, the operator ends the line and the next line starts
  with the operand - `a &&` then `b`, not `a` then `&& b`. Binary operators, `is`/`as`, the pattern
  combinators `and`/`or`, and both halves of `?:`; not `.`, `=>`, or the `:` of a base list or
  constructor initializer. The code fix moves only the operator and leaves the expression alone - a
  wrapped condition or ternary is fine as it is. An existing repository is converted in one pass
  with `dotnet format analyzers --diagnostics NOTA0002 --severity warn`.
- **`UA1000` and `UA1001`** enforce the using layout: System, then third party, then yours, as blocks
  separated by a blank line, one run per vendor. An existing repository is converted in one pass with
  `dotnet format analyzers --diagnostics UA1000 UA1001 --severity warn`.
- **Do not set `dotnet_sort_system_directives_first` or `dotnet_separate_import_directive_groups`.**
  Not even to `false`. This package leaves both keys out on purpose, and an `.editorconfig` entry
  beats a global analyzer config entry, so putting one back is the one override here that breaks
  something. Their presence at any value arms the organize-imports stage of `dotnet format style`,
  which sorts flat-alphabetically after System and so puts your namespaces above the vendors -
  the inverse of what `UA1000` requires. The two then take turns: the style stage reorders, the
  analyzers stage puts it back, the file on disk never changes, and `dotnet format` reports nothing
  to do while `dotnet format --verify-no-changes` exits 2 forever. It is not a diagnostic and no
  severity setting reaches it. Rider is unaffected, so this only bites the command line and CI.

## Turning things off

Any rule can be overridden in the consuming repository's own `.editorconfig`. An `.editorconfig`
entry beats a global analyzer config entry for the same key, so nothing this package sets is a
decision you are stuck with:

```ini
dotnet_diagnostic.IDE0008.severity = suggestion
```

The encoding check is a build task rather than a diagnostic, so it has its own switch:

```xml
<NotaValidateSourceEncoding>false</NotaValidateSourceEncoding>
```

## Upgrading from 2.3

The operator placement convention has flipped. `dotnet_style_operator_placement_when_wrapping` was
`beginning_of_line` and is now `end_of_line`, and `NOTA0002` reports every operator that still leads
a wrapped line - as a warning, so a repository with `TreatWarningsAsErrors` will fail to build until
they are moved. One command moves them all, and changes nothing but whitespace:

```sh
dotnet format analyzers --diagnostics NOTA0002 --severity warn
```

`IDE0024` is now a warning too: an operator overload has a block body, not `=>`. It was always the
preference, just never reported. `dotnet format style --diagnostics IDE0024 --severity warn` converts
them.

The package also sets Rider's wrap keys, but whether Rider reads them from a global analyzer config
rather than `.editorconfig` is unverified. If Rider still puts the operator first when it wraps -
producing fresh warnings - add them to your `.editorconfig`:

```ini
[*.cs]
csharp_wrap_before_binary_opsign = false
csharp_wrap_before_binary_pattern_op = false
csharp_wrap_before_ternary_opsigns = false
```

## Upgrading from 2.1

`SA1412`, which required every source file to carry a byte order mark, is off. It never did anything
for the build - a file without a mark compiles fine, since the compiler assumes UTF-8 when none is
present - and what it was quietly protecting against is now `NOTA0001`'s job, which checks the bytes
rather than the mark.

Nothing forces you to remove the marks you have. If you want to, `tools/de-bom.sh` does it a tree at
a time:

```sh
tools/de-bom.sh /path/to/repo            # report, change nothing
tools/de-bom.sh /path/to/repo --apply    # do it
```

It reports by default, refuses to run on a dirty tree so the result is one revertible commit, and
leaves UTF-16 files alone - their mark is the only record of the encoding, and removing it destroys
the file. Afterwards, every changed file should differ by exactly one line:

```sh
git diff --numstat | awk '$1 != 1 || $2 != 1'
```

Silence means nothing but marks moved.

Two things in that order, and both bite if you get them wrong.

**Take 2.2 first.** On 2.1.x `SA1412` still demands a mark, so stripping them before upgrading breaks
the build on every file.

**Then close the IDE while you strip them.** Visual Studio and Rider decide a file's encoding when
they open it and keep that decision for the buffer. A file that was opened with a mark gets one
written back on the next save, whatever the file on disk now looks like - so an editor left running
quietly undoes the script, file by file, as you touch them. Closing it and reopening afterwards is
enough; the encoding is re-detected from what is actually there.

## Working on this repository

The product here is configuration, and configuration fails silently: a rule that cannot report looks
exactly like a rule being obeyed, because the build is quiet either way. `dotnet_diagnostic.CS8019`
asked for unused usings to be reported and reported nothing for years, with forty-five of them
collected behind it in one consuming solution.

`Nota.CodeAnalysis.Verification` exists to make that noisy. It is a consumer built against files that
break the rules on purpose, and a script that fails if any of them stayed quiet. Read its README
before changing rules.

```sh
./Nota.CodeAnalysis.Verification/verify.sh            # the rules report
./Nota.CodeAnalysis.Verification/verify-encoding.sh   # source is valid UTF-8
```

Both run on pull requests as well as on `main`.

Nota's own analysers live in `Nota.CodeAnalysis.Analysers`, their code fixes in
`Nota.CodeAnalysis.Analysers.CodeFixes` - a separate assembly, because a fix needs Workspaces and the
command-line compiler does not carry it. Both reference Roslyn 4.8 and must stay there or below: an
analyser built against a newer compiler than the consumer's SDK is skipped with `CS9057`, a warning,
and its rules silently vanish. `dotnet test` runs their unit tests in
`Nota.CodeAnalysis.Analysers.Test`; a new rule goes in `AnalyzerReleases.Unshipped.md` as well.

Releases are cut by tagging:

```sh
git tag -a v2.3.0 -m "Nota.CodeAnalysis 2.3.0" && git push origin v2.3.0
```

[MinVer](https://github.com/adamralph/minver) derives the package version from that tag on every
build, so nothing in the repository can disagree with what shipped - there is no `<Version>` to edit
or forget to bump. Building straight off a tagged commit gets that tag's version exactly; anything
else gets the next patch as a pre-release with the commit count above the tag, e.g. `2.3.1-alpha.0.4`.
CI checks out full history (`fetch-depth: 0`) so MinVer can see the tags at all - a shallow clone has
none, and would fall back to `0.0.0-alpha.0`.

Merging to `main` builds and verifies but does not publish, and neither do pull requests - releasing
is a separate act from merging.
