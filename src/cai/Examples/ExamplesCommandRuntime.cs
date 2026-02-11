using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class ExamplesCommandRuntime
{
    private readonly IExamplesDictionaryProvider dictionaryProvider;
    private readonly TextWriter stderr;
    private readonly TextWriter stdout;

    public ExamplesCommandRuntime(
        IExamplesDictionaryProvider? dictionaryProvider = null,
        TextWriter? standardOutput = null,
        TextWriter? standardError = null)
    {
        this.dictionaryProvider = dictionaryProvider ?? new ExamplesStaticDictionaryProvider();
        stdout = standardOutput ?? Console.Out;
        stderr = standardError ?? Console.Error;
    }

    public async Task<int> RunListAsync(CancellationToken cancellationToken)
    {
        var examples = dictionaryProvider.GetExamples();
        if (examples.Count == 0)
        {
            await stderr.WriteLineAsync("[ERROR] No embedded examples are available.").ConfigureAwait(false);
            return 1;
        }

        cancellationToken.ThrowIfCancellationRequested();
        await stdout.WriteLineAsync("Available example TOML files:").ConfigureAwait(false);
        foreach (var fileName in examples.Keys.OrderBy(static name => name, StringComparer.Ordinal))
        {
            cancellationToken.ThrowIfCancellationRequested();
            await stdout.WriteLineAsync($"  {fileName}").ConfigureAwait(false);
        }

        return 0;
    }

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

    private static string NormalizePath(string value)
    {
        if (string.Equals(value, "~", StringComparison.Ordinal))
        {
            return ResolveHomeDirectory();
        }

        if (value.StartsWith("~/", StringComparison.Ordinal))
        {
            return Path.GetFullPath(Path.Combine(ResolveHomeDirectory(), value[2..]));
        }

        return Path.GetFullPath(value);
    }

    private static string ResolveHomeDirectory()
    {
        var home = Environment.GetEnvironmentVariable("HOME");
        if (!string.IsNullOrWhiteSpace(home))
        {
            return home;
        }

        var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (!string.IsNullOrWhiteSpace(userProfile))
        {
            return userProfile;
        }

        return Directory.GetCurrentDirectory();
    }
}
