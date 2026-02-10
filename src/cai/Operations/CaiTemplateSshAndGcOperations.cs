namespace ContainAI.Cli.Host;

internal sealed class CaiTemplateSshAndGcOperations : CaiRuntimeSupport
{
    private readonly CaiStopOperations stopOperations;
    private readonly CaiGcOperations gcOperations;
    private readonly CaiTemplateUpgradeOperations templateUpgradeOperations;
    private readonly CaiSshCleanupOperations sshCleanupOperations;

    public CaiTemplateSshAndGcOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IReadOnlyList<string> containAiImagePrefixes,
        Func<string?, string?, string?, string?, CancellationToken, Task<int>> runExportAsync)
        : base(standardOutput, standardError)
    {
        stopOperations = new CaiStopOperations(standardOutput, standardError, runExportAsync);
        gcOperations = new CaiGcOperations(standardOutput, standardError, containAiImagePrefixes);
        templateUpgradeOperations = new CaiTemplateUpgradeOperations(standardOutput, standardError);
        sshCleanupOperations = new CaiSshCleanupOperations(standardOutput, standardError);
    }

    public Task<int> RunStopAsync(
        string? containerName,
        bool stopAll,
        bool remove,
        bool force,
        bool exportFirst,
        CancellationToken cancellationToken)
        => stopOperations.RunStopAsync(containerName, stopAll, remove, force, exportFirst, cancellationToken);

    public Task<int> RunGcAsync(
        bool dryRun,
        bool force,
        bool includeImages,
        string ageValue,
        CancellationToken cancellationToken)
        => gcOperations.RunGcAsync(dryRun, force, includeImages, ageValue, cancellationToken);

    public Task<int> RunTemplateUpgradeAsync(
        string? templateName,
        bool dryRun,
        CancellationToken cancellationToken)
        => templateUpgradeOperations.RunTemplateUpgradeAsync(templateName, dryRun, cancellationToken);

    public Task<int> RunSshCleanupAsync(bool dryRun, CancellationToken cancellationToken)
        => sshCleanupOperations.RunSshCleanupAsync(dryRun, cancellationToken);
}
