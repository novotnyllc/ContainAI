using ContainAI.Cli.Host.ConfigManifest;
using ContainAI.Cli.Host.Manifests.Apply;
using ContainAI.Cli.Host.RuntimeSupport.Parsing;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host;

internal static class CaiConfigManifestProcessorFactory
{
    private static readonly string[] ConfigFileNames =
    [
        "config.toml",
        "containai.toml",
    ];

    public static IConfigCommandProcessor CreateConfigCommandProcessor(
        TextWriter standardOutput,
        TextWriter standardError)
        => new ConfigCommandProcessor(
            standardOutput,
            standardError,
            new CaiConfigRuntimeAdapter(
                workspacePath => CaiRuntimeConfigLocator.ResolveConfigPath(workspacePath, ConfigFileNames),
                CaiRuntimeHomePathHelpers.ExpandHomePath,
                CaiRuntimeParseAndTimeHelpers.NormalizeConfigKey,
                (request, normalizedKey) => CaiRuntimeParseAndTimeHelpers.ResolveWorkspaceScope(request.Global, request.Workspace, normalizedKey),
                async (operation, cancellationToken) =>
                {
                    var result = await CaiRuntimeParseAndTimeHelpers.RunTomlAsync(operation, cancellationToken).ConfigureAwait(false);
                    return new TomlProcessResult(result.ExitCode, result.StandardOutput, result.StandardError);
                },
                (workspace, explicitVolume, cancellationToken) =>
                    CaiRuntimePathResolutionHelpers.ResolveDataVolumeAsync(workspace, explicitVolume, ConfigFileNames, cancellationToken)));

    public static IManifestCommandProcessor CreateManifestCommandProcessor(
        TextWriter standardOutput,
        TextWriter standardError,
        IManifestTomlParser manifestTomlParser,
        IManifestApplier manifestApplier)
        => new ManifestCommandProcessor(
            standardOutput,
            standardError,
            manifestTomlParser,
            manifestApplier,
            new ManifestDirectoryResolver(CaiRuntimeHomePathHelpers.ExpandHomePath));
}
