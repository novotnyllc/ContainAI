namespace ContainAI.Cli.Host;

internal interface ICaiDoctorFixTemplateRunner
{
    Task<int> RunAsync(bool fixAll, string? target, string? targetArg, CancellationToken cancellationToken);
}
