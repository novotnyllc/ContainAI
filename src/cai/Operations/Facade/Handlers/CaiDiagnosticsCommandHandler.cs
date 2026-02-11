using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiDiagnosticsCommandHandler
{
    private readonly CaiDiagnosticsAndSetupOperations diagnosticsOperations;

    public CaiDiagnosticsCommandHandler(CaiDiagnosticsAndSetupOperations caiDiagnosticsAndSetupOperations)
        => diagnosticsOperations = caiDiagnosticsAndSetupOperations ?? throw new ArgumentNullException(nameof(caiDiagnosticsAndSetupOperations));

    public Task<int> RunStatusAsync(StatusCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return diagnosticsOperations.RunStatusAsync(options.Json, options.Verbose, options.Workspace, options.Container, cancellationToken);
    }

    public Task<int> RunDoctorAsync(DoctorCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return diagnosticsOperations.RunDoctorAsync(options.Json, options.BuildTemplates, options.ResetLima, cancellationToken);
    }

    public Task<int> RunDoctorFixAsync(DoctorFixCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return diagnosticsOperations.RunDoctorFixAsync(options.All, options.DryRun, options.Target, options.TargetArg, cancellationToken);
    }

    public Task<int> RunValidateAsync(ValidateCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return diagnosticsOperations.RunDoctorAsync(options.Json, buildTemplates: false, resetLima: false, cancellationToken);
    }

    public Task<int> RunSetupAsync(SetupCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return diagnosticsOperations.RunSetupAsync(
            dryRun: options.DryRun,
            verbose: options.Verbose,
            skipTemplates: options.SkipTemplates,
            showHelp: false,
            cancellationToken);
    }

    public Task<int> RunVersionAsync(CancellationToken cancellationToken)
        => diagnosticsOperations.RunVersionAsync(json: false, cancellationToken);
}
