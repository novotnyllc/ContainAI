namespace ContainAI.Cli.Host;

internal sealed partial class CaiDiagnosticsAndSetupOperations : CaiRuntimeSupport
{
    private readonly CaiDiagnosticsStatusOperations statusOperations;
    private readonly CaiDoctorOperations doctorOperations;
    private readonly CaiSetupOperations setupOperations;
    private readonly CaiDoctorFixOperations doctorFixOperations;

    public CaiDiagnosticsAndSetupOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        Func<bool, CancellationToken, Task<int>> runSshCleanupAsync)
        : base(standardOutput, standardError)
    {
        var templateRestoreOperations = new CaiTemplateRestoreOperations(standardOutput, standardError);
        statusOperations = new CaiDiagnosticsStatusOperations(standardOutput, standardError);
        doctorOperations = new CaiDoctorOperations(standardOutput, standardError);
        setupOperations = new CaiSetupOperations(
            standardOutput,
            standardError,
            templateRestoreOperations,
            cancellationToken => doctorOperations.RunDoctorAsync(
                outputJson: false,
                buildTemplates: false,
                resetLima: false,
                cancellationToken));
        doctorFixOperations = new CaiDoctorFixOperations(
            standardOutput,
            standardError,
            runSshCleanupAsync,
            templateRestoreOperations);
    }
}
