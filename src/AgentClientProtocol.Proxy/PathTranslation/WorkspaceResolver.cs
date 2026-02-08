// Workspace root resolution
using System.Diagnostics;
using CliWrap;
using CliWrap.Buffered;

namespace AgentClientProtocol.Proxy.PathTranslation;

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
        => await ResolveAsync(cwd, ExecuteGitRootLookupAsync, cancellationToken).ConfigureAwait(false);

    internal static async Task<string> ResolveAsync(
        string cwd,
        Func<string, CancellationToken, Task<BufferedCommandResult>> gitRootLookup,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(gitRootLookup);

        // Try git root first
        try
        {
            var result = await gitRootLookup(cwd, cancellationToken).ConfigureAwait(false);

            if (result.ExitCode == 0 && !string.IsNullOrWhiteSpace(result.StandardOutput))
            {
                return result.StandardOutput.Trim();
            }
        }
        catch (InvalidOperationException ex) when (!cancellationToken.IsCancellationRequested)
        {
            // Git invocation failed; fall back to workspace marker walk.
            Trace.TraceInformation("WorkspaceResolver git lookup failed: {0}", ex.Message);
        }
        catch (IOException ex) when (!cancellationToken.IsCancellationRequested)
        {
            // Git output capture failed; fall back to workspace marker walk.
            Trace.TraceInformation("WorkspaceResolver git output read failed: {0}", ex.Message);
        }
        catch (System.ComponentModel.Win32Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            // Git executable not available; fall back to workspace marker walk.
            Trace.TraceInformation("WorkspaceResolver git executable unavailable: {0}", ex.Message);
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

    private static Task<BufferedCommandResult> ExecuteGitRootLookupAsync(string cwd, CancellationToken cancellationToken)
        => Cli.Wrap("git")
            .WithArguments(args => args
                .Add("-C").Add(cwd)
                .Add("rev-parse")
                .Add("--show-toplevel"))
            .WithValidation(CommandResultValidation.None)
            .ExecuteBufferedAsync(cancellationToken);
}
