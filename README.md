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

## What you have to configure yourself

One key, and only one. UsingLayoutAnalyser sorts usings into System, then third party, then *your*
namespaces - and it cannot know what yours are called. Put this in the consuming repository's
`.editorconfig`:

```ini
[*.cs]
usinglayout.first_party_prefixes = Nota
```

Comma-separated for several roots. Left unset the scheme degrades to System-then-everything-else,
which still works but stops telling your code apart from a vendor's.

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

Any rule can be overridden in the consuming repository's own `.editorconfig`, which takes precedence
over this package's global config:

```ini
dotnet_diagnostic.IDE0008.severity = suggestion
```

The encoding check is a build task rather than a diagnostic, so it has its own switch:

```xml
<NotaValidateSourceEncoding>false</NotaValidateSourceEncoding>
```

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

Releases are cut by bumping `<Version>` in `Nota.CodeAnalysis/Nota.CodeAnalysis.csproj` and merging
to `main`; the pipeline packs and pushes. Pull request builds verify but never publish.
