namespace ContainAI.Cli.Host.Devcontainer;

internal interface IDevcontainerServiceBootstrap
{
    Task<int> VerifySysboxAsync(CancellationToken cancellationToken);

    Task<int> StartSshdAsync(CancellationToken cancellationToken);

    Task<int> StartDockerdAsync(CancellationToken cancellationToken);
}

internal sealed class DevcontainerServiceBootstrap : IDevcontainerServiceBootstrap
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

    public Task<int> VerifySysboxAsync(CancellationToken cancellationToken)
        => sysboxVerificationService.VerifySysboxAsync(cancellationToken);

    public Task<int> StartSshdAsync(CancellationToken cancellationToken)
        => sshdStartupService.StartSshdAsync(cancellationToken);

    public Task<int> StartDockerdAsync(CancellationToken cancellationToken)
        => dockerdStartupService.StartDockerdAsync(cancellationToken);

    private static DevcontainerSysboxVerificationService CreateSysboxVerificationService(
        IDevcontainerProcessHelpers processHelpers,
        TextWriter standardOutput,
        TextWriter standardError)
    {
        ArgumentNullException.ThrowIfNull(processHelpers);
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        return new DevcontainerSysboxVerificationService(processHelpers, standardOutput, standardError);
    }

    private static DevcontainerSshdStartupService CreateSshdStartupService(
        IDevcontainerProcessHelpers processHelpers,
        TextWriter standardOutput,
        TextWriter standardError,
        Func<string, string?> environmentVariableReader)
    {
        ArgumentNullException.ThrowIfNull(processHelpers);
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        ArgumentNullException.ThrowIfNull(environmentVariableReader);
        return new DevcontainerSshdStartupService(processHelpers, standardOutput, standardError, environmentVariableReader);
    }

    private static DevcontainerDockerdStartupService CreateDockerdStartupService(
        IDevcontainerProcessHelpers processHelpers,
        TextWriter standardOutput,
        TextWriter standardError)
    {
        ArgumentNullException.ThrowIfNull(processHelpers);
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        return new DevcontainerDockerdStartupService(processHelpers, standardOutput, standardError);
    }
}
