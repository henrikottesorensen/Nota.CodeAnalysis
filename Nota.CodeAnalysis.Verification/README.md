# Nota.CodeAnalysis.Verification

Checks that the rules this repository ships actually report. Nothing here is shipped or consumed:
`IsPackable` is false, it is in no package, and nothing depends on it.

## Why it exists

The product of this repository is configuration, and configuration fails silently. A rule that is
misspelled, superseded, or simply incapable of reporting looks exactly like a rule that is being
obeyed - the build is quiet either way.

That is not hypothetical. `dotnet_diagnostic.CS8019.severity = warning` asked for unused usings to be
reported, and reported nothing, for as long as anyone can tell: CS8019 is emitted hidden by the
compiler and a severity in config does not raise it. One consuming solution had forty-five unused
directives behind it. Every build was green.

So this project is a consumer, built on purpose against files that break the rules, and a script that
fails if any of them stayed quiet.

## Running it

```sh
./verify.sh            # the rules report
./verify-encoding.sh   # source files are valid UTF-8
./verify-package.sh    # the rules survive being packaged
```

All three run in the pipeline, on pull requests as well as on `main`. All exit non-zero on failure
and name what went wrong.

## How it is put together

`Samples/` is excluded from compilation unless `VerifyRules` is set:

```xml
<Compile Remove="Samples/**" />
<Compile Include="Samples/**" Condition="'$(VerifyRules)' == 'true'" />
```

Some of the rules are error severity - `IDE0008` is - so compiling the samples would fail any
ordinary build of the solution, including the one the pipeline runs before it gets here. `verify.sh`
passes `-p:VerifyRules=true`; every other build gets an empty assembly.

The project also declares the same properties `build/Nota.CodeAnalysis.props` gives a consumer, and
`verify.sh` fails if the props file stops setting one of them. Otherwise this project could drift
into testing a configuration nobody actually receives - and `GenerateDocumentationFile` in particular
looks redundant and is not: without it `IDE0005` silently stops reporting.

## What `verify.sh` asserts

`Samples/Broken.cs` breaks each of these deliberately.

| Rule      | What it catches                              |
|-----------|----------------------------------------------|
| `IDE0005` | an unused using - what CS8019 never did       |
| `IDE0008` | `var` instead of an explicit type             |
| `UA1000`  | using directives out of order                 |
| `SA1208`  | System usings not placed first                |
| `SA1516`  | no blank line after the System group          |

## What `verify-encoding.sh` asserts

Every source file is valid UTF-8, or UTF-16 carrying a BOM.

This is the guard that let `SA1412` be switched off. SA1412 demanded a byte order mark, which was
never what anyone wanted, but it was the only thing standing between the build and a file saved as
Windows-1252 - and such a file compiles with no warning at all, putting U+FFFD replacement characters
straight into the assembly. No analyser can report that: by the time an analyser runs, the text has
already been decoded. It is also a property of `.resx` and `.json` files, which no analyser reads.

BOM-marked UTF-16 is accepted rather than flagged. svcutil and EF migrations emit it, the compiler
reads it correctly, and those files must keep their BOM - it is the only record of their encoding.

It cannot catch a wrong encoding that happens to produce valid UTF-8, the classic `â€œ` mojibake,
which is indistinguishable from someone writing those characters on purpose.

## Adding a rule

Break it in `Samples/Broken.cs`, then add its id to `expected` in `verify.sh`.

**Watch it fail before you trust it.** Set the rule's severity to `none` in the globalconfig and run
`verify.sh`; it should fail naming that rule. A check nobody has seen fail is not a check - which is
the whole reason this project exists.

## What `verify-package.sh` asserts

That the rules survive packaging, which the other two cannot see. They run inside the solution, where
the globalconfig is imported directly and the analysers are referenced by the project itself - so a
rule can be reported here while no consumer receives it. That is not theoretical - it happened twice
while this project was being written, both times caught before merging:

- **UsingLayoutAnalyser was built against a newer Roslyn than the SDK running it.** The compiler
  answered `CS9057`, a warning, and skipped the analyser. Green build, no using rules.
- **The threading analyser acquired `PrivateAssets` during a version bump**, which stops a reference
  reaching consumers. `VSTHRD100` went on firing inside this solution while consumers got nothing.

So it packs, installs into a throwaway project from a local feed, and compiles a file that breaks one
rule per analyser - plus a deliberately mis-encoded file for `NOTA0001`, which proves
`build/Nota.CodeAnalysis.targets` was packed and imported. It fails on `CS9057` too, since that is a
warning nothing else would notice.

It packs under a throwaway version like `0.0.0-verify.20260802143000`. That is not cosmetic: NuGet
extracts a package once per version into the global cache, so re-packing `2.2.0` and installing
`2.2.0` gets whatever was extracted first, and the change under test never reaches the consumer. This
script passed cleanly against a regression it was written to catch until the version was made unique.

## What none of them cover

The scripts are POSIX `sh` and run on `ubuntu-latest`. On a Windows agent they would need porting.

`verify-package.sh` needs network on a cold cache, for the throwaway project's own dependencies.
