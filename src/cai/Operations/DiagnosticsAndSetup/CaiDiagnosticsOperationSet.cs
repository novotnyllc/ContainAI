namespace ContainAI.Cli.Host;

internal sealed class CaiDiagnosticsOperationSet
{
    public CaiDiagnosticsOperationSet(
        CaiDiagnosticsStatusOperations statusOperations,
        CaiDoctorOperations doctorOperations,
        CaiSetupOperations setupOperations,
        CaiDoctorFixOperations doctorFixOperations)
    {
        StatusOperations = statusOperations ?? throw new ArgumentNullException(nameof(statusOperations));
        DoctorOperations = doctorOperations ?? throw new ArgumentNullException(nameof(doctorOperations));
        SetupOperations = setupOperations ?? throw new ArgumentNullException(nameof(setupOperations));
        DoctorFixOperations = doctorFixOperations ?? throw new ArgumentNullException(nameof(doctorFixOperations));
    }

    public CaiDiagnosticsStatusOperations StatusOperations { get; }

    public CaiDoctorOperations DoctorOperations { get; }

    public CaiSetupOperations SetupOperations { get; }

    public CaiDoctorFixOperations DoctorFixOperations { get; }
}
