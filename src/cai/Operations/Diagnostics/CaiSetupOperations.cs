using ContainAI.Cli.Host.Operations.Diagnostics.Setup;

namespace ContainAI.Cli.Host;

internal sealed class CaiSetupOperations
{
    private const string SetupUsage = "Usage: cai setup [--dry-run] [--verbose] [--skip-templates]";

    private readonly TextWriter stdout;
    private readonly CaiSetupDryRunReporter dryRunReporter;
    private readonly CaiSetupRuntimeExecutor runtimeExecutor;

    public CaiSetupOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        CaiTemplateRestoreOperations templateRestoreOperations,
        Func<CancellationToken, Task<int>> runDoctorPostSetupAsync)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        dryRunReporter = new CaiSetupDryRunReporter(standardOutput);
        runtimeExecutor = new CaiSetupRuntimeExecutor(
            standardOutput,
            standardError,
            templateRestoreOperations,
            runDoctorPostSetupAsync);
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
            await stdout.WriteLineAsync(SetupUsage).ConfigureAwait(false);
            return 0;
        }

        var setupPaths = CaiSetupPathResolver.ResolveSetupPaths();
        if (dryRun)
        {
            await dryRunReporter.WriteAsync(setupPaths, skipTemplates).ConfigureAwait(false);
            return 0;
        }

        return await runtimeExecutor.RunAsync(setupPaths, verbose, skipTemplates, cancellationToken).ConfigureAwait(false);
    }
}
