namespace ContainAI.Cli.Host;

internal sealed class CaiDoctorFixOperations
{
    private readonly ICaiDoctorFixTargetOperations targetOperations;
    private readonly ICaiDoctorFixEnvironmentInitializer environmentInitializer;
    private readonly ICaiDoctorFixTemplateRunner templateRunner;
    private readonly ICaiDoctorFixContainerRunner containerRunner;

    public CaiDoctorFixOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        Func<bool, CancellationToken, Task<int>> runSshCleanupAsync,
        CaiTemplateRestoreOperations templateRestoreOperations)
        : this(
            new CaiDoctorFixTargetOperations(standardOutput),
            new CaiDoctorFixEnvironmentInitializer(standardOutput, runSshCleanupAsync),
            new CaiDoctorFixTemplateRunner(templateRestoreOperations),
            new CaiDoctorFixContainerRunner(standardOutput, standardError))
    {
    }

    internal CaiDoctorFixOperations(
        ICaiDoctorFixTargetOperations caiDoctorFixTargetOperations,
        ICaiDoctorFixEnvironmentInitializer caiDoctorFixEnvironmentInitializer,
        ICaiDoctorFixTemplateRunner caiDoctorFixTemplateRunner,
        ICaiDoctorFixContainerRunner caiDoctorFixContainerRunner)
    {
        targetOperations = caiDoctorFixTargetOperations ?? throw new ArgumentNullException(nameof(caiDoctorFixTargetOperations));
        environmentInitializer = caiDoctorFixEnvironmentInitializer ?? throw new ArgumentNullException(nameof(caiDoctorFixEnvironmentInitializer));
        templateRunner = caiDoctorFixTemplateRunner ?? throw new ArgumentNullException(nameof(caiDoctorFixTemplateRunner));
        containerRunner = caiDoctorFixContainerRunner ?? throw new ArgumentNullException(nameof(caiDoctorFixContainerRunner));
    }

    public async Task<int> RunDoctorFixAsync(
        bool fixAll,
        bool dryRun,
        string? target,
        string? targetArg,
        CancellationToken cancellationToken)
    {
        if (await targetOperations.TryWriteAvailableTargetsAsync(target, fixAll).ConfigureAwait(false))
        {
            return 0;
        }

        await environmentInitializer.InitializeAsync(dryRun, cancellationToken).ConfigureAwait(false);

        var templateResult = await templateRunner.RunAsync(fixAll, target, targetArg, cancellationToken).ConfigureAwait(false);
        if (templateResult != 0)
        {
            return templateResult;
        }

        var containerResult = await containerRunner.RunAsync(fixAll, target, targetArg, cancellationToken).ConfigureAwait(false);
        if (containerResult != 0)
        {
            return containerResult;
        }

        return 0;
    }
}
