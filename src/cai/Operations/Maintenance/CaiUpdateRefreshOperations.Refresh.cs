namespace ContainAI.Cli.Host;

internal sealed partial class CaiUpdateRefreshOperations
{
    public async Task<int> RunRefreshAsync(bool rebuild, bool showHelp, CancellationToken cancellationToken)
    {
        if (showHelp)
        {
            await stdout.WriteLineAsync("Usage: cai refresh [--rebuild] [--verbose]").ConfigureAwait(false);
            return 0;
        }

        var channel = await ResolveChannelAsync(cancellationToken).ConfigureAwait(false);
        var baseImage = string.Equals(channel, "nightly", StringComparison.Ordinal)
            ? "ghcr.io/novotnyllc/containai:nightly"
            : "ghcr.io/novotnyllc/containai:latest";

        await stdout.WriteLineAsync($"Pulling {baseImage}...").ConfigureAwait(false);
        var pull = await DockerCaptureAsync(["pull", baseImage], cancellationToken).ConfigureAwait(false);
        if (pull.ExitCode != 0)
        {
            await stderr.WriteLineAsync(pull.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        if (!rebuild)
        {
            await stdout.WriteLineAsync("Refresh complete.").ConfigureAwait(false);
            return 0;
        }

        var templatesRoot = ResolveTemplatesDirectory();
        if (!Directory.Exists(templatesRoot))
        {
            await stderr.WriteLineAsync($"Template directory not found: {templatesRoot}").ConfigureAwait(false);
            return 1;
        }

        var failures = 0;
        foreach (var templateDir in Directory.EnumerateDirectories(templatesRoot))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var templateName = Path.GetFileName(templateDir);
            var dockerfile = Path.Combine(templateDir, "Dockerfile");
            if (!File.Exists(dockerfile))
            {
                continue;
            }

            var imageName = $"containai-template-{templateName}:local";
            var build = await DockerCaptureAsync(
                [
                    "build",
                    "--build-arg", $"BASE_IMAGE={baseImage}",
                    "-t", imageName,
                    "-f", dockerfile,
                    templateDir,
                ],
                cancellationToken).ConfigureAwait(false);

            if (build.ExitCode != 0)
            {
                failures++;
                await stderr.WriteLineAsync($"Template rebuild failed for '{templateName}': {build.StandardError.Trim()}").ConfigureAwait(false);
                continue;
            }

            await stdout.WriteLineAsync($"Rebuilt template '{templateName}' as {imageName}").ConfigureAwait(false);
        }

        return failures == 0 ? 0 : 1;
    }
}
