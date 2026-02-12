using System.Text.Json;

namespace ContainAI.Cli.Host.Devcontainer.InitLinks;

internal interface IDevcontainerFeatureInitLinkSpecLoader
{
    Task<LinkSpecDocument?> LoadLinkSpecForInitAsync(CancellationToken cancellationToken);
}

internal sealed class DevcontainerFeatureInitLinkSpecLoader : IDevcontainerFeatureInitLinkSpecLoader
{
    private readonly TextWriter stderr;

    public DevcontainerFeatureInitLinkSpecLoader(TextWriter stderr)
        => this.stderr = stderr ?? throw new ArgumentNullException(nameof(stderr));

    public async Task<LinkSpecDocument?> LoadLinkSpecForInitAsync(CancellationToken cancellationToken)
    {
        if (!Directory.Exists(DevcontainerFeaturePaths.DefaultDataDir))
        {
            await stderr.WriteLineAsync($"Warning: Data volume not mounted at {DevcontainerFeaturePaths.DefaultDataDir}").ConfigureAwait(false);
            await stderr.WriteLineAsync("Run \"cai import\" on host, then rebuild container with dataVolume option").ConfigureAwait(false);
            return null;
        }

        if (!File.Exists(DevcontainerFeaturePaths.DefaultLinkSpecPath))
        {
            await stderr.WriteLineAsync($"Warning: link-spec.json not found at {DevcontainerFeaturePaths.DefaultLinkSpecPath}").ConfigureAwait(false);
            await stderr.WriteLineAsync("Feature may not be fully installed").ConfigureAwait(false);
            return null;
        }

        var linkSpecJson = await File.ReadAllTextAsync(DevcontainerFeaturePaths.DefaultLinkSpecPath, cancellationToken).ConfigureAwait(false);
        var linkSpec = JsonSerializer.Deserialize(linkSpecJson, DevcontainerFeatureJsonContext.Default.LinkSpecDocument);
        if (linkSpec?.Links is null || linkSpec.Links.Count == 0)
        {
            await stderr.WriteLineAsync("Warning: link-spec has no links").ConfigureAwait(false);
            return null;
        }

        return linkSpec;
    }
}
