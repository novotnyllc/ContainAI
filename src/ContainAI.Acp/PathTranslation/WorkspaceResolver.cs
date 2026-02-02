// Workspace root resolution
using CliWrap;
using CliWrap.Buffered;

namespace ContainAI.Acp.PathTranslation;

/// <summary>
/// Resolves the workspace root from a given directory.
/// </summary>
public static class WorkspaceResolver
{
    /// <summary>
    /// Resolves the workspace root for a given directory.
    /// Checks git root first, then walks up looking for .containai/config.toml.
    /// Falls back to the original directory if no workspace marker is found.
    /// </summary>
    /// <param name="cwd">The starting directory.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The workspace root path.</returns>
    public static async Task<string> ResolveAsync(string cwd, CancellationToken cancellationToken = default)
    {
        // Try git root first
        try
        {
            var result = await Cli.Wrap("git")
                .WithArguments(args => args
                    .Add("-C").Add(cwd)
                    .Add("rev-parse")
                    .Add("--show-toplevel"))
                .WithValidation(CommandResultValidation.None)
                .ExecuteBufferedAsync(cancellationToken);

            if (result.ExitCode == 0 && !string.IsNullOrWhiteSpace(result.StandardOutput))
            {
                return result.StandardOutput.Trim();
            }
        }
        catch
        {
            // Git not available or failed
        }

        // Walk up looking for .containai/config.toml
        var dir = new DirectoryInfo(cwd);
        while (dir != null)
        {
            var configPath = Path.Combine(dir.FullName, ".containai", "config.toml");
            if (File.Exists(configPath))
            {
                return dir.FullName;
            }
            dir = dir.Parent;
        }

        // Fall back to cwd
        return cwd;
    }
}
