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
SerilogAnalyzer, and UsingLayoutAnalyser. Around 400 rule severities are set in
`content/Nota.CodeAnalysis.globalconfig`.

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
- **`UA1000` and `UA1001`** enforce the using layout: System, then third party, then yours, as blocks
  separated by a blank line, one run per vendor. An existing repository is converted in one pass with
  `dotnet format analyzers --diagnostics UA1000 UA1001 --severity warn`.

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

Releases are cut by tagging:

```sh
git tag -a v2.3.0 -m "Nota.CodeAnalysis 2.3.0" && git push origin v2.3.0
```

The tag is the version, so nothing in the repository can disagree with what shipped. `<Version>` in
the csproj is only a local default, for anyone packing by hand.

Merging to `main` builds and verifies but does not publish, and neither do pull requests - releasing
is a separate act from merging.
