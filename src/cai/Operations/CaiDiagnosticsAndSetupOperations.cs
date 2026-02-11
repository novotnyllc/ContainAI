namespace ContainAI.Cli.Host;

internal sealed class CaiDiagnosticsAndSetupOperations
{
    private readonly CaiDiagnosticsStatusOperations statusOperations;
    private readonly CaiDoctorOperations doctorOperations;
    private readonly CaiSetupOperations setupOperations;
    private readonly CaiDoctorFixOperations doctorFixOperations;
    private readonly ICaiDockerCommandForwarder dockerCommandForwarder;
    private readonly ICaiVersionCommandWriter versionCommandWriter;

    public CaiDiagnosticsAndSetupOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        Func<bool, CancellationToken, Task<int>> runSshCleanupAsync)
        : this(
            CaiDiagnosticsOperationSetFactory.Create(standardOutput, standardError, runSshCleanupAsync),
            new CaiDockerCommandForwarder(),
            new CaiVersionCommandWriter(standardOutput))
    {
    }

    internal CaiDiagnosticsAndSetupOperations(
        CaiDiagnosticsOperationSet operationSet,
        ICaiDockerCommandForwarder caiDockerCommandForwarder,
        ICaiVersionCommandWriter caiVersionCommandWriter)
    {
        ArgumentNullException.ThrowIfNull(operationSet);
        statusOperations = operationSet.StatusOperations;
        doctorOperations = operationSet.DoctorOperations;
        setupOperations = operationSet.SetupOperations;
        doctorFixOperations = operationSet.DoctorFixOperations;
        dockerCommandForwarder = caiDockerCommandForwarder ?? throw new ArgumentNullException(nameof(caiDockerCommandForwarder));
        versionCommandWriter = caiVersionCommandWriter ?? throw new ArgumentNullException(nameof(caiVersionCommandWriter));
    }

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

    public static async Task<int> RunDockerAsync(IReadOnlyList<string> dockerArguments, CancellationToken cancellationToken)
        => await new CaiDockerCommandForwarder().RunAsync(dockerArguments, cancellationToken).ConfigureAwait(false);

    public async Task<int> RunVersionAsync(bool json, CancellationToken cancellationToken)
        => await versionCommandWriter.WriteVersionAsync(json, cancellationToken).ConfigureAwait(false);
}
