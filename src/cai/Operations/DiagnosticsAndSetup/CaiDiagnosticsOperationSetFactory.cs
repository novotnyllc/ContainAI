namespace ContainAI.Cli.Host;

internal static class CaiDiagnosticsOperationSetFactory
{
    public static CaiDiagnosticsOperationSet Create(
        TextWriter standardOutput,
        TextWriter standardError,
        Func<bool, CancellationToken, Task<int>> runSshCleanupAsync)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        ArgumentNullException.ThrowIfNull(runSshCleanupAsync);

        var templateRestoreOperations = new CaiTemplateRestoreOperations(standardOutput, standardError);
        var statusOperations = new CaiDiagnosticsStatusOperations(standardOutput, standardError);
        var doctorOperations = new CaiDoctorOperations(standardOutput, standardError);
        var setupOperations = new CaiSetupOperations(
            standardOutput,
            standardError,
            templateRestoreOperations,
            cancellationToken => doctorOperations.RunDoctorAsync(
                outputJson: false,
                buildTemplates: false,
                resetLima: false,
                cancellationToken));
        var doctorFixOperations = new CaiDoctorFixOperations(
            standardOutput,
            standardError,
            runSshCleanupAsync,
            templateRestoreOperations);

        return new CaiDiagnosticsOperationSet(
            statusOperations,
            doctorOperations,
            setupOperations,
            doctorFixOperations);
    }
}
