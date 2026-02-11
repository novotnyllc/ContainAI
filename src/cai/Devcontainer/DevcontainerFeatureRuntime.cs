namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerFeatureRuntime
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly IDevcontainerFeatureInstallWorkflow installWorkflow;
    private readonly IDevcontainerFeatureInitWorkflow initWorkflow;
    private readonly IDevcontainerFeatureStartWorkflow startWorkflow;

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
        ArgumentNullException.ThrowIfNull(configService);
        ArgumentNullException.ThrowIfNull(processHelpers);
        ArgumentNullException.ThrowIfNull(userEnvironmentSetup);
        ArgumentNullException.ThrowIfNull(serviceBootstrap);
        ArgumentNullException.ThrowIfNull(environmentVariableReader);

        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));

        var settingsFactory = new DevcontainerFeatureSettingsFactory(configService, environmentVariableReader);
        var configLoader = new DevcontainerFeatureConfigLoader(configService, stderr);
        installWorkflow = new DevcontainerFeatureInstallWorkflow(stdout, stderr, processHelpers, userEnvironmentSetup, settingsFactory);
        initWorkflow = new DevcontainerFeatureInitWorkflow(stdout, stderr, processHelpers, userEnvironmentSetup, serviceBootstrap, configLoader);
        startWorkflow = new DevcontainerFeatureStartWorkflow(stdout, stderr, serviceBootstrap, configLoader);
    }

    internal DevcontainerFeatureRuntime(
        TextWriter standardOutput,
        TextWriter standardError,
        IDevcontainerFeatureInstallWorkflow installWorkflow,
        IDevcontainerFeatureInitWorkflow initWorkflow,
        IDevcontainerFeatureStartWorkflow startWorkflow)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        this.installWorkflow = installWorkflow ?? throw new ArgumentNullException(nameof(installWorkflow));
        this.initWorkflow = initWorkflow ?? throw new ArgumentNullException(nameof(initWorkflow));
        this.startWorkflow = startWorkflow ?? throw new ArgumentNullException(nameof(startWorkflow));
    }
}
