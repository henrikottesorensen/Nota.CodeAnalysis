# Installable Nuget Package with Nota Codestyle, Stylecop and Code Analysis rules.

Note: You MIGHT have to restart Visual Studio for it to pickup the injected .editorconfig, after the first build.

## Known issues
Requires $(SolutionDir) to be defined. If you build from a single .csproj, it will be undefined. Use a solution file, or set a SolutionDir property with `dotnet build --property:SolutionDir=../ MyProject.csproj`
