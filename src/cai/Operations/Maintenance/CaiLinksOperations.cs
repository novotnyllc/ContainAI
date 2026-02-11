using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Parsing;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host;

internal sealed class CaiLinksOperations
{
    private static readonly string[] ConfigFileNames =
    [
        "config.toml",
        "containai.toml",
    ];

    private readonly TextWriter stderr;
    private readonly ContainerLinkRepairService containerLinkRepairService;

    public CaiLinksOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        ContainerLinkRepairService containerLinkRepairService)
    {
        _ = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        this.containerLinkRepairService = containerLinkRepairService ?? throw new ArgumentNullException(nameof(containerLinkRepairService));
    }

    public async Task<int> RunLinksAsync(
        string subcommand,
        string? containerName,
        string? workspace,
        bool dryRun,
        bool quiet,
        CancellationToken cancellationToken)
    {
        var resolvedWorkspace = string.IsNullOrWhiteSpace(workspace)
            ? Directory.GetCurrentDirectory()
            : Path.GetFullPath(CaiRuntimeHomePathHelpers.ExpandHomePath(workspace));

        if (string.IsNullOrWhiteSpace(containerName))
        {
            containerName = await CaiRuntimeCommandParsingHelpers
                .ResolveWorkspaceContainerNameAsync(resolvedWorkspace, stderr, ConfigFileNames, cancellationToken)
                .ConfigureAwait(false);
        }

        if (string.IsNullOrWhiteSpace(containerName))
        {
            await stderr.WriteLineAsync($"Unable to resolve container for workspace: {resolvedWorkspace}").ConfigureAwait(false);
            return 1;
        }

        var stateResult = await CaiRuntimeDockerHelpers.DockerCaptureAsync(
            ["inspect", "--format", "{{.State.Status}}", containerName],
            cancellationToken).ConfigureAwait(false);

        if (stateResult.ExitCode != 0)
        {
            await stderr.WriteLineAsync($"Container not found: {containerName}").ConfigureAwait(false);
            return 1;
        }

        var state = stateResult.StandardOutput.Trim();
        if (string.Equals(subcommand, "check", StringComparison.Ordinal))
        {
            if (!string.Equals(state, "running", StringComparison.Ordinal))
            {
                await stderr.WriteLineAsync($"Container '{containerName}' is not running (state: {state}).").ConfigureAwait(false);
                return 1;
            }
        }
        else if (!string.Equals(state, "running", StringComparison.Ordinal))
        {
            var startResult = await CaiRuntimeDockerHelpers.DockerCaptureAsync(["start", containerName], cancellationToken).ConfigureAwait(false);
            if (startResult.ExitCode != 0)
            {
                await stderr.WriteLineAsync($"Failed to start container '{containerName}': {startResult.StandardError.Trim()}").ConfigureAwait(false);
                return 1;
            }
        }

        var mode = string.Equals(subcommand, "check", StringComparison.Ordinal)
            ? ContainerLinkRepairMode.Check
            : dryRun
                ? ContainerLinkRepairMode.DryRun
                : ContainerLinkRepairMode.Fix;

        return await containerLinkRepairService
            .RunAsync(containerName, mode, quiet, cancellationToken)
            .ConfigureAwait(false);
    }
}
