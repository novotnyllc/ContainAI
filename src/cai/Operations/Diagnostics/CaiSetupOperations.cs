namespace ContainAI.Cli.Host;

internal sealed partial class CaiSetupOperations : CaiRuntimeSupport
{
    private readonly CaiTemplateRestoreOperations templateRestoreOperations;
    private readonly Func<CancellationToken, Task<int>> runDoctorPostSetupAsync;

    public CaiSetupOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        CaiTemplateRestoreOperations templateRestoreOperations,
        Func<CancellationToken, Task<int>> runDoctorPostSetupAsync)
        : base(standardOutput, standardError)
    {
        this.templateRestoreOperations = templateRestoreOperations ?? throw new ArgumentNullException(nameof(templateRestoreOperations));
        this.runDoctorPostSetupAsync = runDoctorPostSetupAsync ?? throw new ArgumentNullException(nameof(runDoctorPostSetupAsync));
    }

    public async Task<int> RunSetupAsync(
        bool dryRun,
        bool verbose,
        bool skipTemplates,
        bool showHelp,
        CancellationToken cancellationToken)
    {
        if (showHelp)
        {
            await WriteSetupUsageAsync().ConfigureAwait(false);
            return 0;
        }

        var setupPaths = ResolveSetupPaths();

        if (dryRun)
        {
            await WriteSetupDryRunAsync(setupPaths, skipTemplates).ConfigureAwait(false);
            return 0;
        }

        return await RunSetupCoreAsync(setupPaths, verbose, skipTemplates, cancellationToken).ConfigureAwait(false);
    }
}
