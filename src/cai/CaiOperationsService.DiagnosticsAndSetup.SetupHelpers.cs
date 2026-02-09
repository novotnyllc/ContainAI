using System.ComponentModel;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiOperationsService : CaiRuntimeSupport
{
    private static async Task EnsureSshIncludeDirectiveAsync(CancellationToken cancellationToken)
    {
        var userSshConfig = Path.Combine(ResolveHomeDirectory(), ".ssh", "config");
        var includeLine = $"Include {Path.Combine(ResolveHomeDirectory(), ".ssh", "containai.d")}/*.conf";

        Directory.CreateDirectory(Path.GetDirectoryName(userSshConfig)!);
        if (!File.Exists(userSshConfig))
        {
            await File.WriteAllTextAsync(userSshConfig, includeLine + Environment.NewLine, cancellationToken).ConfigureAwait(false);
            return;
        }

        var content = await File.ReadAllTextAsync(userSshConfig, cancellationToken).ConfigureAwait(false);
        if (content.Contains(includeLine, StringComparison.Ordinal))
        {
            return;
        }

        var normalized = content.TrimEnd();
        var merged = string.IsNullOrWhiteSpace(normalized)
            ? includeLine + Environment.NewLine
            : normalized + Environment.NewLine + includeLine + Environment.NewLine;
        await File.WriteAllTextAsync(userSshConfig, merged, cancellationToken).ConfigureAwait(false);
    }

    private async Task<int> RestoreTemplatesAsync(string? templateName, bool includeAll, CancellationToken cancellationToken)
    {
        var sourceRoot = ResolveBundledTemplatesDirectory();
        if (string.IsNullOrWhiteSpace(sourceRoot) || !Directory.Exists(sourceRoot))
        {
            await stderr.WriteLineAsync("Bundled templates not found; skipping template restore.").ConfigureAwait(false);
            return 0;
        }

        var destinationRoot = ResolveTemplatesDirectory();
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

            await CopyDirectoryAsync(source, destination, cancellationToken).ConfigureAwait(false);
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
