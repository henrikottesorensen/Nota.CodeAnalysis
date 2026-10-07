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
SerilogAnalyzer, and UsingLayoutAnalyser. One more, Nota's own (`NOTA0003`, with its code fix), is
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
- **`NOTA0002` is a warning** on a source file carrying a UTF-8 byte order mark. Note that
  `NOTA0001` says nothing about these: a BOM is legal UTF-8, so a marked file is a valid file, and
  the two rules are looking for different things. The mark records nothing - UTF-8 is what the
  compiler assumes when there is no mark at all - and it comes back on its own, which is the actual
  reason this is a rule. An editor decides a file's encoding when it opens it: one that opened a file
  with a mark writes a mark back on every later save, so a single stray file re-marks itself forever
  and spreads to whatever else that editor touches. A warning rather than an error because a mark
  costs nothing at runtime, so a tree that has them should say so on every build rather than be
  unbuildable until someone sweeps it. Which of the several ways to promote a warning actually
  promotes this one is not obvious - see below. UTF-16 is exempt, as under `NOTA0001`.
- **Both only look at files you wrote.** Sources under the NuGet cache and generated sources under
  `obj` are compiled into your project but are not yours to re-save, so neither rule reports them.
  `Microsoft.NET.Test.Sdk` is the one that made this necessary: it contributes a marked file of its
  own to every test project, from a read-only shared cache that restores it the moment it is touched.
  Reporting that left `NotaValidateSourceEncoding=false` as the only route to a clean build, which
  throws away `NOTA0001` too - a rule against corruption talking people into switching off the only
  guard against it.
- **`NOTA0003`**: when an expression wraps, the operator ends the line and the next line starts
  with the operand - `a &&` then `b`, not `a` then `&& b`. Binary operators, `is`/`as`, the pattern
  combinators `and`/`or`, and both halves of `?:`; not `.`, `=>`, or the `:` of a base list or
  constructor initializer. The code fix moves only the operator and leaves the expression alone - a
  wrapped condition or ternary is fine as it is. An existing repository is converted in one pass
  with `dotnet format analyzers --diagnostics NOTA0003 --severity warn`.
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
- **`UA1002`** is what tells you the above, rather than leaving you to remember it. It reports once
  per project on either of those keys being present at any value, and on
  `dotnet_diagnostic.SA1210.severity` being turned up to `warning` or `error` - SA1210 has a fix of
  its own, and under `dotnet format` its fix and `UA1000`'s undo each other, so the file changes on
  every run. It arrived with UsingLayoutAnalyser 0.4.0. Silence from it is not a clean bill of
  health: SA1210 left unset is StyleCop's own default, which no analyser can read, so unset is
  unknown rather than safe.

## Turning things off

Any rule can be overridden in the consuming repository's own `.editorconfig`. An `.editorconfig`
entry beats a global analyzer config entry for the same key, so nothing this package sets is a
decision you are stuck with:

```ini
dotnet_diagnostic.IDE0008.severity = suggestion
```

The encoding checks are a build task rather than diagnostics, so they have their own switches:

```xml
<NotaValidateSourceEncoding>false</NotaValidateSourceEncoding>  <!-- NOTA0001 and NOTA0002 -->
<NotaAllowUtf8Bom>true</NotaAllowUtf8Bom>                       <!-- NOTA0002 only -->
```

`NOTA0002` is only a warning, so a tree full of marks still builds; `NotaAllowUtf8Bom` is for
silencing it entirely while that tree waits its turn, and it leaves `NOTA0001` - the one that catches
actual corruption - in place.

### Making it an error, and the one that will not

`NOTA0002` is logged by an MSBuild task, so it never passes through the compiler - and the property
everyone reaches for first is a compiler setting. All four measured:

| Set this                                | `NOTA0002` becomes |
|-----------------------------------------|--------------------|
| `dotnet build -warnaserror`             | an error           |
| `<WarningsAsErrors>NOTA0002</...>`      | an error           |
| `<MSBuildTreatWarningsAsErrors>true</...>` | an error        |
| `<TreatWarningsAsErrors>true</...>`     | **still a warning**|

The first row is the one that matters, and it is the arrangement to want: `-warnaserror` is the
MSBuild engine's switch rather than the compiler's, so it takes task warnings with it, and a pipeline
already carrying that flag fails on a marked file without anyone configuring anything. That is the
split this severity is chosen for - a mark says so on a developer's build and stops it at the gate.
`-warnaserror:CS0168`, or any code list that omits `NOTA0002`, leaves it alone.

The last row is the genuine surprise. `TreatWarningsAsErrors` is a compiler property, and this
warning never goes near the compiler, so a repository relying on that alone gets no gate - use the
switch or `WarningsAsErrors` if you want one.

## Keeping marks out, rather than failing on them

`NOTA0002` reports a file that already has a mark. What stops one being written in the first place is
a line in the consuming repository's own `.editorconfig`, which Rider and Visual Studio both honour:

```ini
[*]
charset = utf-8
```

That is `utf-8` meaning *without* a mark; `utf-8-bom` is the spelling that asks for one. Worth setting
even with `NOTA0002` on - the rule reports a file that has been re-marked, and this stops it being
written that way at all.

It does not help a file that is already open. The encoding is decided when the editor opens a file
and kept for the buffer, so a tree is cleaned with the IDE closed and the setting keeps it clean
afterwards.

That one line also puts `dotnet format` to work, which is the part worth knowing:

| `.editorconfig`         | `dotnet format whitespace`        | `--verify-no-changes` on a marked file |
|-------------------------|-----------------------------------|----------------------------------------|
| `charset = utf-8`       | strips the mark                   | exits 2                                |
| `charset = utf-8-bom`   | **adds** a mark to every file     | exits 2 on an unmarked one             |
| no `charset` key        | leaves marks exactly as they are  | exits 0                                |

All three measured, on `dotnet format whitespace` with nothing else wrong in the file - the mark is a
change in its own right, not something that has to ride along with a reformat. So with `utf-8` set,
a repository already running `dotnet format` in CI fails on a re-marked file without `NOTA0002`
needing to say anything, and fixes it by running the same command without `--verify-no-changes`.

Two things follow from the second row. `utf-8-bom` is not merely the opposite setting - it will mark
files that never had a mark, and it fights `NOTA0002` on every build. And `charset` unset is why
marks survive a tree that formats itself religiously.

`dotnet format` cannot fix `NOTA0002` as such. The rule is logged by an MSBuild task, so
`dotnet format analyzers` never sees it and no code fix exists for it; what strips the mark is the
`charset` key, working on its own. Nor does it leave UTF-16 alone the way `tools/de-bom.sh` does -
measured, it transcodes such a file to UTF-8, which preserves the text and still compiles, but
arrives as a whole-file diff, and a regenerated service reference or migration will be UTF-16 again
next time the generator runs.

## Upgrading from 2.3

The operator placement convention has flipped. `dotnet_style_operator_placement_when_wrapping` was
`beginning_of_line` and is now `end_of_line`, and `NOTA0003` reports every operator that still leads
a wrapped line - as a warning, so a repository with `TreatWarningsAsErrors` will fail to build until
they are moved. One command moves them all, and changes nothing but whitespace:

```sh
dotnet format analyzers --diagnostics NOTA0003 --severity warn
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

## Upgrading

The two encoding changes came one version apart and land in the same place, so they are described
together. Where 2.1 demanded a mark and 2.2 stopped caring, 2.3 fails the build on one.

**On 2.1**, `SA1412` required every source file to carry a byte order mark. It never did anything for
the build - a file without a mark compiles fine, since the compiler assumes UTF-8 when none is
present - and what it was quietly protecting against became `NOTA0001`'s job, which checks the bytes
rather than the mark.

**On 2.2**, `SA1412` is off and nothing objects to a mark either way. That is the version to strip
them on, and the marks left behind are why 2.3 exists: with no rule pointing at them they come back,
one editor buffer at a time.

**On 2.3**, `NOTA0002` warns on any compiled file that has one, and a pipeline building with
`-warnaserror` fails on it - which is the point of the severity rather than a side effect of it. A
developer's build says which files are marked and carries on; CI declines to merge them.

So the marks have to go before the first build that matters, not eventually. Strip them, set
`charset = utf-8` in the same commit, and the tree stays clean on its own. `NotaAllowUtf8Bom` is
there for a repository that needs to upgrade today and sweep next week, and it leaves `NOTA0001`
running while it waits.

`tools/de-bom.sh` strips a tree at a time:

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

Three things in that order, and each bites if you get it wrong.

**Take 2.2 or later first.** On 2.1.x `SA1412` still demands a mark, so stripping them before
upgrading breaks the build on every file.

**Then close the IDE while you strip them.** Visual Studio and Rider decide a file's encoding when
they open it and keep that decision for the buffer. A file that was opened with a mark gets one
written back on the next save, whatever the file on disk now looks like - so an editor left running
quietly undoes the script, file by file, as you touch them. Closing it and reopening afterwards is
enough; the encoding is re-detected from what is actually there.

**Then set `charset = utf-8` before reopening it.** Stripping the marks is a one-off; the setting is
what stops them being written again. Do it in the other order and the first save of the first file
you touch has already put one back.

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
./Nota.CodeAnalysis.Verification/verify-encoding.sh   # source is UTF-8, and unmarked
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
