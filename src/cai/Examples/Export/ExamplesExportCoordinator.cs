using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class ExamplesExportCoordinator(
    TextWriter standardOutput,
    TextWriter standardError,
    IExamplesOutputPathResolver outputPathResolver) : IExamplesExportCoordinator
{
    public async Task<int> RunAsync(
        IReadOnlyDictionary<string, string> examples,
        ExamplesExportCommandOptions options,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(examples);
        ArgumentNullException.ThrowIfNull(options);

        if (string.IsNullOrWhiteSpace(options.OutputDir))
        {
            await standardError.WriteLineAsync("[ERROR] --output-dir is required.").ConfigureAwait(false);
            return 1;
        }

        if (examples.Count == 0)
        {
            await standardError.WriteLineAsync("[ERROR] No embedded examples are available.").ConfigureAwait(false);
            return 1;
        }

        var outputDir = outputPathResolver.NormalizePath(options.OutputDir);
        Directory.CreateDirectory(outputDir);

        foreach (var fileName in examples.Keys)
        {
            var destination = Path.Combine(outputDir, fileName);
            if (File.Exists(destination) && !options.Force)
            {
                await standardError.WriteLineAsync($"[ERROR] File already exists: {destination} (use --force to overwrite)").ConfigureAwait(false);
                return 1;
            }
        }

        foreach (var (fileName, contents) in examples.OrderBy(static pair => pair.Key, StringComparer.Ordinal))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var destination = Path.Combine(outputDir, fileName);
            await File.WriteAllTextAsync(destination, contents + Environment.NewLine, cancellationToken).ConfigureAwait(false);
        }

        await standardOutput.WriteLineAsync($"[OK] Wrote {examples.Count} example file(s) to {outputDir}").ConfigureAwait(false);
        return 0;
    }
}
