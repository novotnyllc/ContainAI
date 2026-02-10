namespace ContainAI.Cli.Host;

internal sealed class CaiDiagnosticsStatusCommandDispatcher : CaiRuntimeSupport
{
    public CaiDiagnosticsStatusCommandDispatcher(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
    }

    public Task<string?> ResolveContainerForWorkspaceAsync(string workspace, CancellationToken cancellationToken)
        => ResolveWorkspaceContainerNameAsync(workspace, cancellationToken);

    public static async Task<IReadOnlyList<string>> DiscoverContainerContextsAsync(string container, CancellationToken cancellationToken)
        => await FindContainerContextsAsync(container, cancellationToken).ConfigureAwait(false);

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
        var result = await DockerCaptureForContextAsync(context, args, cancellationToken).ConfigureAwait(false);
        return new CaiDiagnosticsStatusCommandResult(result.ExitCode, result.StandardOutput, result.StandardError);
    }
}
