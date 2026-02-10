using System.Text.Json;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeCommandService
{
    private async Task<int> RunInitCoreAsync(SystemInitCommandOptions options, CancellationToken cancellationToken)
    {
        var parsed = optionParser.ParseInitCommandOptions(options);
        var quiet = parsed.Quiet;
        var dataDir = parsed.DataDir;
        var homeDir = parsed.HomeDir;
        var manifestsDir = parsed.ManifestsDir;
        var templateHooksDir = parsed.TemplateHooksDir;
        var workspaceHooksDir = parsed.WorkspaceHooksDir;
        var workspaceDir = parsed.WorkspaceDir;

        try
        {
            await LogInfoAsync(quiet, "ContainAI initialization starting...").ConfigureAwait(false);

            await UpdateAgentPasswordAsync().ConfigureAwait(false);
            await EnsureVolumeStructureAsync(dataDir, manifestsDir, quiet).ConfigureAwait(false);
            await LoadEnvFileAsync(Path.Combine(dataDir, ".env"), quiet).ConfigureAwait(false);
            await MigrateGitConfigAsync(dataDir, quiet).ConfigureAwait(false);
            await SetupGitConfigAsync(dataDir, homeDir, quiet).ConfigureAwait(false);
            await SetupWorkspaceSymlinkAsync(workspaceDir, quiet).ConfigureAwait(false);
            await ProcessUserManifestsAsync(dataDir, homeDir, quiet).ConfigureAwait(false);

            await RunHooksAsync(templateHooksDir, workspaceDir, homeDir, quiet, cancellationToken).ConfigureAwait(false);
            await RunHooksAsync(workspaceHooksDir, workspaceDir, homeDir, quiet, cancellationToken).ConfigureAwait(false);

            await LogInfoAsync(quiet, "ContainAI initialization complete").ConfigureAwait(false);
            return 0;
        }
        catch (InvalidOperationException ex)
        {
            return await WriteInitErrorAsync(ex).ConfigureAwait(false);
        }
        catch (IOException ex)
        {
            return await WriteInitErrorAsync(ex).ConfigureAwait(false);
        }
        catch (UnauthorizedAccessException ex)
        {
            return await WriteInitErrorAsync(ex).ConfigureAwait(false);
        }
        catch (JsonException ex)
        {
            return await WriteInitErrorAsync(ex).ConfigureAwait(false);
        }
        catch (ArgumentException ex)
        {
            return await WriteInitErrorAsync(ex).ConfigureAwait(false);
        }
        catch (NotSupportedException ex)
        {
            return await WriteInitErrorAsync(ex).ConfigureAwait(false);
        }
    }
}
