using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host;

internal interface ICaiDoctorFixEnvironmentInitializer
{
    Task InitializeAsync(bool dryRun, CancellationToken cancellationToken);
}
