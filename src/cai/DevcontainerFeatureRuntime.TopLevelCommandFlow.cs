using System.Text.Json;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerFeatureRuntime
{
    private async Task<int> RunInstallCoreAsync(SystemDevcontainerInstallCommandOptions options, CancellationToken cancellationToken)
    {
        var featureDirectory = options.FeatureDir;

        if (!TryCreateFeatureConfig(out var settings, out var featureConfigError))
        {
            await stderr.WriteLineAsync(featureConfigError).ConfigureAwait(false);
            return 1;
        }

        if (!await processHelpers.CommandExistsAsync("apt-get", cancellationToken).ConfigureAwait(false))
        {
            await stderr.WriteLineAsync("ContainAI feature requires Debian/Ubuntu image with apt-get.").ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync("ContainAI: Installing feature...").ConfigureAwait(false);
        Directory.CreateDirectory("/usr/local/share/containai");
        Directory.CreateDirectory("/usr/local/lib/containai");

        var configJson = JsonSerializer.Serialize(
            settings,
            JsonContext.Default.FeatureConfig);
        await File.WriteAllTextAsync(DefaultConfigPath, configJson + Environment.NewLine, cancellationToken).ConfigureAwait(false);
        await stdout.WriteLineAsync("  Configuration saved").ConfigureAwait(false);

        if (!string.IsNullOrWhiteSpace(featureDirectory))
        {
            var sourceLinkSpec = Path.Combine(featureDirectory, "link-spec.json");
            if (File.Exists(sourceLinkSpec))
            {
                File.Copy(sourceLinkSpec, DefaultLinkSpecPath, overwrite: true);
                await stdout.WriteLineAsync("  Installed: link-spec.json").ConfigureAwait(false);
            }
            else
            {
                await stdout.WriteLineAsync("  Note: link-spec.json not bundled - symlinks will be skipped").ConfigureAwait(false);
            }
        }

        await processHelpers.RunAsRootAsync("apt-get", ["update", "-qq"], cancellationToken).ConfigureAwait(false);

        if (settings.EnableSsh)
        {
            await processHelpers.RunAsRootAsync("apt-get", ["install", "-y", "-qq", "openssh-server"], cancellationToken).ConfigureAwait(false);
            await processHelpers.RunAsRootAsync("mkdir", ["-p", "/var/run/sshd"], cancellationToken).ConfigureAwait(false);
            await stdout.WriteLineAsync("    Installed: openssh-server").ConfigureAwait(false);
        }

        if (settings.InstallDocker)
        {
            await processHelpers.RunAsRootAsync("apt-get", ["install", "-y", "-qq", "curl", "ca-certificates"], cancellationToken).ConfigureAwait(false);
            await stdout.WriteLineAsync("    Installed: curl, ca-certificates").ConfigureAwait(false);
            await processHelpers.RunAsRootAsync("sh", ["-c", "curl -fsSL https://get.docker.com | sh"], cancellationToken).ConfigureAwait(false);
            await userEnvironmentSetup.AddUserToDockerGroupIfPresentAsync("vscode", cancellationToken).ConfigureAwait(false);
            await userEnvironmentSetup.AddUserToDockerGroupIfPresentAsync("node", cancellationToken).ConfigureAwait(false);
            await stdout.WriteLineAsync("    Installed: docker (DinD starts via postStartCommand)").ConfigureAwait(false);
        }

        await processHelpers.RunAsRootAsync("apt-get", ["clean"], cancellationToken).ConfigureAwait(false);
        await processHelpers.RunAsRootAsync("sh", ["-c", "rm -rf /var/lib/apt/lists/*"], cancellationToken).ConfigureAwait(false);

        await stdout.WriteLineAsync("ContainAI feature installed successfully").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Data volume: {settings.DataVolume}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Credentials: {settings.EnableCredentials}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  SSH: {settings.EnableSsh}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Docker: {settings.InstallDocker}").ConfigureAwait(false);
        return 0;
    }

    public async Task<int> RunInitAsync(CancellationToken cancellationToken)
    {
        var settings = await LoadFeatureConfigOrWriteErrorAsync(cancellationToken).ConfigureAwait(false);
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

        if (!Directory.Exists(DefaultDataDir))
        {
            await stderr.WriteLineAsync($"Warning: Data volume not mounted at {DefaultDataDir}").ConfigureAwait(false);
            await stderr.WriteLineAsync("Run \"cai import\" on host, then rebuild container with dataVolume option").ConfigureAwait(false);
            return 0;
        }

        if (!File.Exists(DefaultLinkSpecPath))
        {
            await stderr.WriteLineAsync($"Warning: link-spec.json not found at {DefaultLinkSpecPath}").ConfigureAwait(false);
            await stderr.WriteLineAsync("Feature may not be fully installed").ConfigureAwait(false);
            return 0;
        }

        var linkSpecJson = await File.ReadAllTextAsync(DefaultLinkSpecPath, cancellationToken).ConfigureAwait(false);
        var linkSpec = JsonSerializer.Deserialize(linkSpecJson, JsonContext.Default.LinkSpecDocument);
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

            if (!settings.EnableCredentials && CredentialTargets.Contains(link.Target))
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

    public async Task<int> RunStartAsync(CancellationToken cancellationToken)
    {
        var settings = await LoadFeatureConfigOrWriteErrorAsync(cancellationToken).ConfigureAwait(false);
        if (settings is null)
        {
            return 1;
        }

        var verifyCode = await serviceBootstrap.VerifySysboxAsync(cancellationToken).ConfigureAwait(false);
        if (verifyCode != 0)
        {
            return verifyCode;
        }

        if (settings.EnableSsh)
        {
            var sshExit = await serviceBootstrap.StartSshdAsync(cancellationToken).ConfigureAwait(false);
            if (sshExit != 0)
            {
                return sshExit;
            }
        }

        var dockerExit = await serviceBootstrap.StartDockerdAsync(cancellationToken).ConfigureAwait(false);
        if (dockerExit != 0)
        {
            await stderr.WriteLineAsync("Warning: DinD not available").ConfigureAwait(false);
        }

        await stdout.WriteLineAsync("[OK] ContainAI devcontainer ready").ConfigureAwait(false);
        return 0;
    }

    public Task<int> RunVerifySysboxAsync(CancellationToken cancellationToken)
        => serviceBootstrap.VerifySysboxAsync(cancellationToken);

    private async Task<FeatureConfig?> LoadFeatureConfigOrWriteErrorAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(DefaultConfigPath))
        {
            await stderr.WriteLineAsync($"ERROR: Configuration file not found: {DefaultConfigPath}").ConfigureAwait(false);
            return null;
        }

        var settings = await configService.LoadFeatureConfigAsync(DefaultConfigPath, cancellationToken).ConfigureAwait(false);
        if (settings is null)
        {
            await stderr.WriteLineAsync($"ERROR: Failed to parse configuration file: {DefaultConfigPath}").ConfigureAwait(false);
            return null;
        }

        return settings;
    }
}
