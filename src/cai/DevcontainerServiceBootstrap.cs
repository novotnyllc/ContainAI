namespace ContainAI.Cli.Host;

internal interface IDevcontainerServiceBootstrap
{
    Task<int> VerifySysboxAsync(CancellationToken cancellationToken);

    Task<int> StartSshdAsync(CancellationToken cancellationToken);

    Task<int> StartDockerdAsync(CancellationToken cancellationToken);
}

internal sealed partial class DevcontainerServiceBootstrap : IDevcontainerServiceBootstrap
{
    private readonly IDevcontainerSysboxVerificationService sysboxVerificationService;
    private readonly IDevcontainerSshdStartupService sshdStartupService;
    private readonly IDevcontainerDockerdStartupService dockerdStartupService;

    public DevcontainerServiceBootstrap(
        IDevcontainerProcessHelpers processHelpers,
        TextWriter standardOutput,
        TextWriter standardError,
        Func<string, string?> environmentVariableReader)
        : this(
            CreateSysboxVerificationService(processHelpers, standardOutput, standardError),
            CreateSshdStartupService(processHelpers, standardOutput, standardError, environmentVariableReader),
            CreateDockerdStartupService(processHelpers, standardOutput, standardError))
    {
    }

    internal DevcontainerServiceBootstrap(
        IDevcontainerSysboxVerificationService devcontainerSysboxVerificationService,
        IDevcontainerSshdStartupService devcontainerSshdStartupService,
        IDevcontainerDockerdStartupService devcontainerDockerdStartupService)
    {
        sysboxVerificationService = devcontainerSysboxVerificationService ?? throw new ArgumentNullException(nameof(devcontainerSysboxVerificationService));
        sshdStartupService = devcontainerSshdStartupService ?? throw new ArgumentNullException(nameof(devcontainerSshdStartupService));
        dockerdStartupService = devcontainerDockerdStartupService ?? throw new ArgumentNullException(nameof(devcontainerDockerdStartupService));
    }
}
