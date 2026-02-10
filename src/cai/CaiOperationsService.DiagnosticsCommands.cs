using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiOperationsService
{
    public Task<int> RunStatusAsync(StatusCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return diagnosticsAndSetupOperations.RunStatusAsync(options.Json, options.Verbose, options.Workspace, options.Container, cancellationToken);
    }

    public Task<int> RunDoctorAsync(DoctorCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return diagnosticsAndSetupOperations.RunDoctorAsync(options.Json, options.BuildTemplates, options.ResetLima, cancellationToken);
    }

    public Task<int> RunDoctorFixAsync(DoctorFixCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return diagnosticsAndSetupOperations.RunDoctorFixAsync(options.All, options.DryRun, options.Target, options.TargetArg, cancellationToken);
    }

    public Task<int> RunValidateAsync(ValidateCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return diagnosticsAndSetupOperations.RunDoctorAsync(options.Json, buildTemplates: false, resetLima: false, cancellationToken);
    }

    public Task<int> RunSetupAsync(SetupCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return diagnosticsAndSetupOperations.RunSetupAsync(
            dryRun: options.DryRun,
            verbose: options.Verbose,
            skipTemplates: options.SkipTemplates,
            showHelp: false,
            cancellationToken);
    }

    public Task<int> RunVersionAsync(CancellationToken cancellationToken)
        => diagnosticsAndSetupOperations.RunVersionAsync(json: false, cancellationToken);
}
