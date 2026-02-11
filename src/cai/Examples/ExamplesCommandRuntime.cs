using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class ExamplesCommandRuntime
{
    private readonly IExamplesDictionaryProvider dictionaryProvider;
    private readonly ExamplesListCommandRunner listCommandRunner;
    private readonly ExamplesExportCoordinator exportCoordinator;

    public ExamplesCommandRuntime(
        IExamplesDictionaryProvider? dictionaryProvider = null,
        TextWriter? standardOutput = null,
        TextWriter? standardError = null)
    {
        var stdout = standardOutput ?? Console.Out;
        var stderr = standardError ?? Console.Error;
        this.dictionaryProvider = dictionaryProvider ?? new ExamplesStaticDictionaryProvider();
        listCommandRunner = new ExamplesListCommandRunner(stdout, stderr);
        exportCoordinator = new ExamplesExportCoordinator(stdout, stderr, new ExamplesOutputPathResolver());
    }

    public async Task<int> RunListAsync(CancellationToken cancellationToken)
        => await listCommandRunner.RunAsync(dictionaryProvider.GetExamples(), cancellationToken).ConfigureAwait(false);

    public async Task<int> RunExportAsync(ExamplesExportCommandOptions options, CancellationToken cancellationToken)
        => await exportCoordinator.RunAsync(dictionaryProvider.GetExamples(), options, cancellationToken).ConfigureAwait(false);
}
