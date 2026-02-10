namespace ContainAI.Cli.Host;

internal sealed partial class CaiUpdateRefreshOperations : CaiRuntimeSupport
{
    private readonly Func<bool, bool, bool, CancellationToken, Task<int>> runDoctorAsync;

    public CaiUpdateRefreshOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        Func<bool, bool, bool, CancellationToken, Task<int>> runDoctorAsync)
        : base(standardOutput, standardError)
        => this.runDoctorAsync = runDoctorAsync ?? throw new ArgumentNullException(nameof(runDoctorAsync));
}
