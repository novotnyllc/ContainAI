using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerFeatureRuntime
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly IDevcontainerFeatureConfigService configService;
    private readonly IDevcontainerProcessHelpers processHelpers;
    private readonly IDevcontainerUserEnvironmentSetup userEnvironmentSetup;
    private readonly IDevcontainerServiceBootstrap serviceBootstrap;
    private readonly Func<string, string?> environmentVariableReader;

    public DevcontainerFeatureRuntime(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new DevcontainerFeatureConfigService(),
            new DevcontainerProcessHelpers(),
            Environment.GetEnvironmentVariable)
    {
    }

    internal DevcontainerFeatureRuntime(
        TextWriter standardOutput,
        TextWriter standardError,
        IDevcontainerFeatureConfigService configService,
        IDevcontainerProcessHelpers processHelpers,
        Func<string, string?> environmentVariableReader)
        : this(
            standardOutput,
            standardError,
            configService,
            processHelpers,
            new DevcontainerUserEnvironmentSetup(processHelpers, standardOutput, environmentVariableReader),
            new DevcontainerServiceBootstrap(processHelpers, standardOutput, standardError, environmentVariableReader),
            environmentVariableReader)
    {
    }

    internal DevcontainerFeatureRuntime(
        TextWriter standardOutput,
        TextWriter standardError,
        IDevcontainerFeatureConfigService configService,
        IDevcontainerProcessHelpers processHelpers,
        IDevcontainerUserEnvironmentSetup userEnvironmentSetup,
        IDevcontainerServiceBootstrap serviceBootstrap,
        Func<string, string?> environmentVariableReader)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        this.configService = configService ?? throw new ArgumentNullException(nameof(configService));
        this.processHelpers = processHelpers ?? throw new ArgumentNullException(nameof(processHelpers));
        this.userEnvironmentSetup = userEnvironmentSetup ?? throw new ArgumentNullException(nameof(userEnvironmentSetup));
        this.serviceBootstrap = serviceBootstrap ?? throw new ArgumentNullException(nameof(serviceBootstrap));
        this.environmentVariableReader = environmentVariableReader ?? throw new ArgumentNullException(nameof(environmentVariableReader));
    }
}
