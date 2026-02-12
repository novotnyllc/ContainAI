namespace ContainAI.Cli.Host;

internal interface ICaiDoctorFixTargetOperations
{
    Task<bool> TryWriteAvailableTargetsAsync(string? target, bool fixAll);
}
