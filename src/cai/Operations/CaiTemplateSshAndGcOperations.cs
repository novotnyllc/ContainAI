namespace ContainAI.Cli.Host;

internal sealed class CaiTemplateSshAndGcOperations
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
        : this(
            standardOutput,
            standardError,
            containAiImagePrefixes,
            runExportAsync,
            new CaiSshCleanupOperations(standardOutput, standardError))
    {
    }

    internal CaiTemplateSshAndGcOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IReadOnlyList<string> containAiImagePrefixes,
        Func<string?, string?, string?, string?, CancellationToken, Task<int>> runExportAsync,
        CaiSshCleanupOperations caiSshCleanupOperations)
    {
        stopOperations = new CaiStopOperations(standardOutput, standardError, runExportAsync);

        var ageParser = new CaiGcAgeParser();
        var candidateCollector = new CaiGcCandidateCollector(standardError);
        var confirmationPrompt = new CaiGcConfirmationPrompt(standardOutput, standardError);
        var containerPruner = new CaiGcContainerPruner(standardOutput);
        var imagePruner = new CaiGcImagePruner(standardOutput, containAiImagePrefixes);
        gcOperations = new CaiGcOperations(
            standardOutput,
            standardError,
            ageParser,
            candidateCollector,
            confirmationPrompt,
            containerPruner,
            imagePruner);

        templateUpgradeOperations = new CaiTemplateUpgradeOperations(standardOutput, standardError);
        sshCleanupOperations = caiSshCleanupOperations ?? throw new ArgumentNullException(nameof(caiSshCleanupOperations));
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
