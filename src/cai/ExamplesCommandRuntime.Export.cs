using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class ExamplesCommandRuntime
{
    public async Task<int> RunExportAsync(ExamplesExportCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);

        if (string.IsNullOrWhiteSpace(options.OutputDir))
        {
            await stderr.WriteLineAsync("[ERROR] --output-dir is required.").ConfigureAwait(false);
            return 1;
        }

        var examples = dictionaryProvider.GetExamples();
        if (examples.Count == 0)
        {
            await stderr.WriteLineAsync("[ERROR] No embedded examples are available.").ConfigureAwait(false);
            return 1;
        }
        var outputDir = NormalizePath(options.OutputDir);
        Directory.CreateDirectory(outputDir);

        foreach (var fileName in examples.Keys)
        {
            var destination = Path.Combine(outputDir, fileName);
            if (File.Exists(destination) && !options.Force)
            {
                await stderr.WriteLineAsync($"[ERROR] File already exists: {destination} (use --force to overwrite)").ConfigureAwait(false);
                return 1;
            }
        }

        foreach (var (fileName, contents) in examples.OrderBy(static pair => pair.Key, StringComparer.Ordinal))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var destination = Path.Combine(outputDir, fileName);
            await File.WriteAllTextAsync(destination, contents + Environment.NewLine, cancellationToken).ConfigureAwait(false);
        }

        await stdout.WriteLineAsync($"[OK] Wrote {examples.Count} example file(s) to {outputDir}").ConfigureAwait(false);
        return 0;
    }
}
