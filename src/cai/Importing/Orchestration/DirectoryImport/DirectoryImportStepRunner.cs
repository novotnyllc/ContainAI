namespace ContainAI.Cli.Host;

internal sealed class DirectoryImportStepRunner
{
    private readonly IReadOnlyList<IDirectoryImportStep> steps;

    public DirectoryImportStepRunner(IReadOnlyList<IDirectoryImportStep> directoryImportSteps)
        => steps = directoryImportSteps ?? throw new ArgumentNullException(nameof(directoryImportSteps));

    public async Task<int> RunAsync(DirectoryImportContext context, CancellationToken cancellationToken)
    {
        foreach (var step in steps)
        {
            var stepCode = await step.ExecuteAsync(context, cancellationToken).ConfigureAwait(false);
            if (stepCode != 0)
            {
                return stepCode;
            }
        }

        return 0;
    }
}
