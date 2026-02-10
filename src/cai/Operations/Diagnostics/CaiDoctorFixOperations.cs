namespace ContainAI.Cli.Host;

internal sealed partial class CaiDoctorFixOperations : CaiRuntimeSupport
{
    private readonly Func<bool, CancellationToken, Task<int>> runSshCleanupAsync;
    private readonly CaiTemplateRestoreOperations templateRestoreOperations;

    public CaiDoctorFixOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        Func<bool, CancellationToken, Task<int>> runSshCleanupAsync,
        CaiTemplateRestoreOperations templateRestoreOperations)
        : base(standardOutput, standardError)
    {
        this.runSshCleanupAsync = runSshCleanupAsync ?? throw new ArgumentNullException(nameof(runSshCleanupAsync));
        this.templateRestoreOperations = templateRestoreOperations ?? throw new ArgumentNullException(nameof(templateRestoreOperations));
    }

    public async Task<int> RunDoctorFixAsync(
        bool fixAll,
        bool dryRun,
        string? target,
        string? targetArg,
        CancellationToken cancellationToken)
    {
        if (await TryWriteAvailableTargetsAsync(target, fixAll).ConfigureAwait(false))
        {
            return 0;
        }

        var containAiDir = Path.Combine(ResolveHomeDirectory(), ".config", "containai");
        var sshDir = Path.Combine(ResolveHomeDirectory(), ".ssh", "containai.d");
        await EnsureDirectoriesAndSshAsync(dryRun, containAiDir, sshDir, cancellationToken).ConfigureAwait(false);

        var templateResult = await RunTemplateFixAsync(fixAll, target, targetArg, cancellationToken).ConfigureAwait(false);
        if (templateResult != 0)
        {
            return templateResult;
        }

        var containerResult = await RunContainerFixAsync(fixAll, target, targetArg, cancellationToken).ConfigureAwait(false);
        if (containerResult != 0)
        {
            return containerResult;
        }

        return 0;
    }
}
