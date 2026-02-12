using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host;

internal sealed class CaiGcImagePruner : ICaiGcImagePruner
{
    private readonly TextWriter stdout;
    private readonly IReadOnlyList<string> containAiImagePrefixes;

    public CaiGcImagePruner(
        TextWriter standardOutput,
        IReadOnlyList<string> containAiImagePrefixes)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        this.containAiImagePrefixes = containAiImagePrefixes ?? throw new ArgumentNullException(nameof(containAiImagePrefixes));
    }

    public async Task<int> PruneAsync(bool dryRun, CancellationToken cancellationToken)
    {
        var failures = 0;
        var images = await CaiRuntimeDockerHelpers.DockerCaptureAsync(["images", "--format", "{{.Repository}}:{{.Tag}} {{.ID}}"], cancellationToken).ConfigureAwait(false);
        if (images.ExitCode != 0)
        {
            return failures;
        }

        foreach (var line in images.StandardOutput.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (parts.Length != 2)
            {
                continue;
            }

            var reference = parts[0];
            var imageId = parts[1];
            if (!containAiImagePrefixes.Any(prefix => reference.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)))
            {
                continue;
            }

            if (dryRun)
            {
                await stdout.WriteLineAsync($"Would remove image {reference}").ConfigureAwait(false);
            }
            else
            {
                var removeImageResult = await CaiRuntimeDockerHelpers.DockerRunAsync(["rmi", imageId], cancellationToken).ConfigureAwait(false);
                if (removeImageResult != 0)
                {
                    failures++;
                }
            }
        }

        return failures;
    }
}
