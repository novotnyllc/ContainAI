using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host;

internal sealed class CaiTemplateUpgradeOperations
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;

    public CaiTemplateUpgradeOperations(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
    }

    public async Task<int> RunTemplateUpgradeAsync(
        string? templateName,
        bool dryRun,
        CancellationToken cancellationToken)
    {
        var templatesRoot = CaiRuntimeConfigRoot.ResolveTemplatesDirectory();
        if (!Directory.Exists(templatesRoot))
        {
            await stderr.WriteLineAsync($"Template directory not found: {templatesRoot}").ConfigureAwait(false);
            return 1;
        }

        var dockerfiles = string.IsNullOrWhiteSpace(templateName)
            ? Directory.EnumerateDirectories(templatesRoot)
                .Select(path => Path.Combine(path, "Dockerfile"))
                .Where(File.Exists)
                .ToArray()
            : [Path.Combine(templatesRoot, templateName, "Dockerfile")];

        var changedCount = 0;
        foreach (var dockerfile in dockerfiles)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!File.Exists(dockerfile))
            {
                continue;
            }

            var content = await File.ReadAllTextAsync(dockerfile, cancellationToken).ConfigureAwait(false);
            if (!TemplateUtilities.TryUpgradeDockerfile(content, out var updated))
            {
                continue;
            }

            changedCount++;
            if (dryRun)
            {
                await stdout.WriteLineAsync($"Would upgrade {dockerfile}").ConfigureAwait(false);
                continue;
            }

            await File.WriteAllTextAsync(dockerfile, updated, cancellationToken).ConfigureAwait(false);
            await stdout.WriteLineAsync($"Upgraded {dockerfile}").ConfigureAwait(false);
        }

        if (changedCount == 0)
        {
            await stdout.WriteLineAsync("No template changes required.").ConfigureAwait(false);
        }

        return 0;
    }
}
