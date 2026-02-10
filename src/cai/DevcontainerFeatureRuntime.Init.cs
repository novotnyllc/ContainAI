using System.Text.Json;

namespace ContainAI.Cli.Host;

internal sealed class DevcontainerFeatureConfigLoader : IDevcontainerFeatureConfigLoader
{
    private readonly IDevcontainerFeatureConfigService configService;
    private readonly TextWriter stderr;

    public DevcontainerFeatureConfigLoader(IDevcontainerFeatureConfigService configService, TextWriter stderr)
    {
        this.configService = configService ?? throw new ArgumentNullException(nameof(configService));
        this.stderr = stderr ?? throw new ArgumentNullException(nameof(stderr));
    }

    public async Task<FeatureConfig?> LoadFeatureConfigOrWriteErrorAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(DevcontainerFeaturePaths.DefaultConfigPath))
        {
            await stderr.WriteLineAsync($"ERROR: Configuration file not found: {DevcontainerFeaturePaths.DefaultConfigPath}").ConfigureAwait(false);
            return null;
        }

        var settings = await configService.LoadFeatureConfigAsync(DevcontainerFeaturePaths.DefaultConfigPath, cancellationToken).ConfigureAwait(false);
        if (settings is null)
        {
            await stderr.WriteLineAsync($"ERROR: Failed to parse configuration file: {DevcontainerFeaturePaths.DefaultConfigPath}").ConfigureAwait(false);
            return null;
        }

        return settings;
    }
}

internal sealed class DevcontainerFeatureInitWorkflow : IDevcontainerFeatureInitWorkflow
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly IDevcontainerProcessHelpers processHelpers;
    private readonly IDevcontainerUserEnvironmentSetup userEnvironmentSetup;
    private readonly IDevcontainerServiceBootstrap serviceBootstrap;
    private readonly IDevcontainerFeatureConfigLoader configLoader;

    public DevcontainerFeatureInitWorkflow(
        TextWriter stdout,
        TextWriter stderr,
        IDevcontainerProcessHelpers processHelpers,
        IDevcontainerUserEnvironmentSetup userEnvironmentSetup,
        IDevcontainerServiceBootstrap serviceBootstrap,
        IDevcontainerFeatureConfigLoader configLoader)
    {
        this.stdout = stdout ?? throw new ArgumentNullException(nameof(stdout));
        this.stderr = stderr ?? throw new ArgumentNullException(nameof(stderr));
        this.processHelpers = processHelpers ?? throw new ArgumentNullException(nameof(processHelpers));
        this.userEnvironmentSetup = userEnvironmentSetup ?? throw new ArgumentNullException(nameof(userEnvironmentSetup));
        this.serviceBootstrap = serviceBootstrap ?? throw new ArgumentNullException(nameof(serviceBootstrap));
        this.configLoader = configLoader ?? throw new ArgumentNullException(nameof(configLoader));
    }

    public async Task<int> RunInitAsync(CancellationToken cancellationToken)
    {
        var settings = await configLoader.LoadFeatureConfigOrWriteErrorAsync(cancellationToken).ConfigureAwait(false);
        if (settings is null)
        {
            return 1;
        }

        var verifyCode = await serviceBootstrap.VerifySysboxAsync(cancellationToken).ConfigureAwait(false);
        if (verifyCode != 0)
        {
            return verifyCode;
        }

        var userHome = await userEnvironmentSetup.DetectUserHomeAsync(settings.RemoteUser, cancellationToken).ConfigureAwait(false);
        await stdout.WriteLineAsync($"ContainAI init: Setting up symlinks in {userHome}").ConfigureAwait(false);

        if (!Directory.Exists(DevcontainerFeaturePaths.DefaultDataDir))
        {
            await stderr.WriteLineAsync($"Warning: Data volume not mounted at {DevcontainerFeaturePaths.DefaultDataDir}").ConfigureAwait(false);
            await stderr.WriteLineAsync("Run \"cai import\" on host, then rebuild container with dataVolume option").ConfigureAwait(false);
            return 0;
        }

        if (!File.Exists(DevcontainerFeaturePaths.DefaultLinkSpecPath))
        {
            await stderr.WriteLineAsync($"Warning: link-spec.json not found at {DevcontainerFeaturePaths.DefaultLinkSpecPath}").ConfigureAwait(false);
            await stderr.WriteLineAsync("Feature may not be fully installed").ConfigureAwait(false);
            return 0;
        }

        var linkSpecJson = await File.ReadAllTextAsync(DevcontainerFeaturePaths.DefaultLinkSpecPath, cancellationToken).ConfigureAwait(false);
        var linkSpec = JsonSerializer.Deserialize(linkSpecJson, DevcontainerFeatureJsonContext.Default.LinkSpecDocument);
        if (linkSpec?.Links is null || linkSpec.Links.Count == 0)
        {
            await stderr.WriteLineAsync("Warning: link-spec has no links").ConfigureAwait(false);
            return 0;
        }

        var created = 0;
        var skipped = 0;
        var sourceHome = string.IsNullOrWhiteSpace(linkSpec.HomeDirectory) ? "/home/agent" : linkSpec.HomeDirectory!;
        foreach (var link in linkSpec.Links)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (link is null || string.IsNullOrWhiteSpace(link.Link) || string.IsNullOrWhiteSpace(link.Target))
            {
                continue;
            }

            if (!settings.EnableCredentials && DevcontainerFeaturePaths.CredentialTargets.Contains(link.Target))
            {
                await stdout.WriteLineAsync($"  [SKIP] {link.Link} (credentials disabled)").ConfigureAwait(false);
                skipped++;
                continue;
            }

            if (!File.Exists(link.Target) && !Directory.Exists(link.Target))
            {
                continue;
            }

            var rewrittenLink = link.Link.StartsWith(sourceHome, StringComparison.Ordinal)
                ? userHome + link.Link[sourceHome.Length..]
                : link.Link;
            var parentDirectory = Path.GetDirectoryName(rewrittenLink);
            if (!string.IsNullOrWhiteSpace(parentDirectory))
            {
                Directory.CreateDirectory(parentDirectory);
            }

            var removeFirst = link.RemoveFirst ?? false;
            if (Directory.Exists(rewrittenLink) && !processHelpers.IsSymlink(rewrittenLink))
            {
                if (!removeFirst)
                {
                    await stderr.WriteLineAsync($"  [FAIL] {rewrittenLink} (directory exists, remove_first not set)").ConfigureAwait(false);
                    continue;
                }

                Directory.Delete(rewrittenLink, recursive: true);
            }
            else if (File.Exists(rewrittenLink) || processHelpers.IsSymlink(rewrittenLink))
            {
                File.Delete(rewrittenLink);
            }

            if (Directory.Exists(link.Target))
            {
                Directory.CreateSymbolicLink(rewrittenLink, link.Target);
            }
            else
            {
                File.CreateSymbolicLink(rewrittenLink, link.Target);
            }

            await stdout.WriteLineAsync($"  [OK] {rewrittenLink} -> {link.Target}").ConfigureAwait(false);
            created++;
        }

        await stdout.WriteAsync($"\nContainAI init complete: {created} symlinks created").ConfigureAwait(false);
        if (skipped > 0)
        {
            await stdout.WriteAsync($", {skipped} credential files skipped").ConfigureAwait(false);
        }

        await stdout.WriteLineAsync().ConfigureAwait(false);
        return 0;
    }
}
