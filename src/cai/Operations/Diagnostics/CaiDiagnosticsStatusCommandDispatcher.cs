using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Parsing;

namespace ContainAI.Cli.Host;

internal sealed class CaiDiagnosticsStatusCommandDispatcher
{
    private static readonly string[] ConfigFileNames =
    [
        "config.toml",
        "containai.toml",
    ];

    private readonly TextWriter stderr;

    public CaiDiagnosticsStatusCommandDispatcher(TextWriter standardOutput, TextWriter standardError)
    {
        _ = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
    }

    public Task<string?> ResolveContainerForWorkspaceAsync(string workspace, CancellationToken cancellationToken) =>
        CaiRuntimeCommandParsingHelpers.ResolveWorkspaceContainerNameAsync(workspace, stderr, ConfigFileNames, cancellationToken);

    public static async Task<IReadOnlyList<string>> DiscoverContainerContextsAsync(string container, CancellationToken cancellationToken)
        => await CaiRuntimeDockerHelpers.FindContainerContextsAsync(container, cancellationToken).ConfigureAwait(false);

    public static Task<CaiDiagnosticsStatusCommandResult> InspectManagedLabelAsync(string context, string container, CancellationToken cancellationToken)
        => ExecuteForContextAsync(
            context,
            ["inspect", "--format", "{{index .Config.Labels \"containai.managed\"}}", "--", container],
            cancellationToken);

    public static Task<CaiDiagnosticsStatusCommandResult> InspectContainerStatusAsync(string context, string container, CancellationToken cancellationToken)
        => ExecuteForContextAsync(
            context,
            ["inspect", "--format", "{{.State.Status}}|{{.Config.Image}}|{{.State.StartedAt}}", "--", container],
            cancellationToken);

    public static Task<CaiDiagnosticsStatusCommandResult> InspectContainerStatsAsync(string context, string container, CancellationToken cancellationToken)
        => ExecuteForContextAsync(
            context,
            ["stats", "--no-stream", "--format", "{{.MemUsage}}|{{.CPUPerc}}", "--", container],
            cancellationToken);

    private static async Task<CaiDiagnosticsStatusCommandResult> ExecuteForContextAsync(
        string context,
        IReadOnlyList<string> args,
        CancellationToken cancellationToken)
    {
        var result = await CaiRuntimeDockerHelpers.DockerCaptureForContextAsync(context, args, cancellationToken).ConfigureAwait(false);
        return new CaiDiagnosticsStatusCommandResult(result.ExitCode, result.StandardOutput, result.StandardError);
    }
}
