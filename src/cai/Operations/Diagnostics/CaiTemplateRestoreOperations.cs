using ContainAI.Cli.Host.RuntimeSupport.Paths;
using ContainAI.Cli.Host.RuntimeSupport.Process;

namespace ContainAI.Cli.Host;

internal sealed class CaiTemplateRestoreOperations
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;

    public CaiTemplateRestoreOperations(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
    }

    public async Task<int> RestoreTemplatesAsync(string? templateName, bool includeAll, CancellationToken cancellationToken)
    {
        var sourceRoot = ResolveBundledTemplatesDirectory();
        if (string.IsNullOrWhiteSpace(sourceRoot) || !Directory.Exists(sourceRoot))
        {
            await stderr.WriteLineAsync("Bundled templates not found; skipping template restore.").ConfigureAwait(false);
            return 0;
        }

        var destinationRoot = CaiRuntimeConfigRoot.ResolveTemplatesDirectory();
        Directory.CreateDirectory(destinationRoot);

        var sourceTemplates = Directory.EnumerateDirectories(sourceRoot).ToArray();
        if (!string.IsNullOrWhiteSpace(templateName) && !includeAll)
        {
            sourceTemplates = sourceTemplates
                .Where(path => string.Equals(Path.GetFileName(path), templateName, StringComparison.Ordinal))
                .ToArray();
        }

        foreach (var source in sourceTemplates)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var template = Path.GetFileName(source);
            var destination = Path.Combine(destinationRoot, template);
            if (Directory.Exists(destination))
            {
                Directory.Delete(destination, recursive: true);
            }

            await CaiRuntimeDirectoryCopier.CopyDirectoryAsync(source, destination, cancellationToken).ConfigureAwait(false);
            await stdout.WriteLineAsync($"Restored template '{template}'").ConfigureAwait(false);
        }

        return 0;
    }

    private static string ResolveBundledTemplatesDirectory()
    {
        var installRoot = InstallMetadata.ResolveInstallDirectory();
        foreach (var candidate in new[]
                 {
                     Path.Combine(installRoot, "templates"),
                     Path.Combine(installRoot, "src", "templates"),
                 })
        {
            if (Directory.Exists(candidate))
            {
                return candidate;
            }
        }

        return string.Empty;
    }
}
