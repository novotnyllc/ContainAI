using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host;

internal sealed class CaiExportOperations
{
    private static readonly string[] ConfigFileNames =
    [
        "config.toml",
        "containai.toml",
    ];

    private readonly TextWriter stdout;
    private readonly TextWriter stderr;

    public CaiExportOperations(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
    }

    public async Task<int> RunExportAsync(
        string? output,
        string? explicitVolume,
        string? container,
        string? workspace,
        CancellationToken cancellationToken)
    {
        workspace ??= Directory.GetCurrentDirectory();
        var volume = string.IsNullOrWhiteSpace(container)
            ? await CaiRuntimePathResolutionHelpers.ResolveDataVolumeAsync(workspace, explicitVolume, ConfigFileNames, cancellationToken).ConfigureAwait(false)
            : await CaiRuntimeDockerHelpers.ResolveDataVolumeFromContainerAsync(container, explicitVolume, cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(volume))
        {
            await stderr.WriteLineAsync("Unable to resolve data volume. Use --data-volume.").ConfigureAwait(false);
            return 1;
        }

        var outputPath = string.IsNullOrWhiteSpace(output)
            ? Path.Combine(Directory.GetCurrentDirectory(), $"containai-export-{DateTime.UtcNow:yyyyMMdd-HHmmss}.tgz")
            : Path.GetFullPath(CaiRuntimeHomePathHelpers.ExpandHomePath(output));

        if (Directory.Exists(outputPath))
        {
            outputPath = Path.Combine(outputPath, $"containai-export-{DateTime.UtcNow:yyyyMMdd-HHmmss}.tgz");
        }

        Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
        var outputDir = Path.GetDirectoryName(outputPath)!;
        var outputFile = Path.GetFileName(outputPath);

        var exportResult = await CaiRuntimeDockerHelpers.DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/mnt/agent-data", "-v", $"{outputDir}:/out", "alpine:3.20", "sh", "-lc", $"tar -C /mnt/agent-data -czf /out/{outputFile} ."],
            cancellationToken).ConfigureAwait(false);
        if (exportResult.ExitCode != 0)
        {
            await stderr.WriteLineAsync(exportResult.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync(outputPath).ConfigureAwait(false);
        return 0;
    }
}
