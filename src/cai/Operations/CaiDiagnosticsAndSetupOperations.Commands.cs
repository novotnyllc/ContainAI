namespace ContainAI.Cli.Host;

internal sealed partial class CaiDiagnosticsAndSetupOperations
{
    public Task<int> RunStatusAsync(
        bool outputJson,
        bool verbose,
        string? workspace,
        string? container,
        CancellationToken cancellationToken)
        => statusOperations.RunStatusAsync(outputJson, verbose, workspace, container, cancellationToken);

    public Task<int> RunDoctorAsync(
        bool outputJson,
        bool buildTemplates,
        bool resetLima,
        CancellationToken cancellationToken)
        => doctorOperations.RunDoctorAsync(outputJson, buildTemplates, resetLima, cancellationToken);

    public Task<int> RunSetupAsync(
        bool dryRun,
        bool verbose,
        bool skipTemplates,
        bool showHelp,
        CancellationToken cancellationToken)
        => setupOperations.RunSetupAsync(dryRun, verbose, skipTemplates, showHelp, cancellationToken);

    public Task<int> RunDoctorFixAsync(
        bool fixAll,
        bool dryRun,
        string? target,
        string? targetArg,
        CancellationToken cancellationToken)
        => doctorFixOperations.RunDoctorFixAsync(fixAll, dryRun, target, targetArg, cancellationToken);
}
