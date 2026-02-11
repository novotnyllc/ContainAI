namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerFeatureInitWorkflow : IDevcontainerFeatureInitWorkflow
{
    private readonly TextWriter stdout;
    private readonly IDevcontainerUserEnvironmentSetup userEnvironmentSetup;
    private readonly IDevcontainerServiceBootstrap serviceBootstrap;
    private readonly IDevcontainerFeatureConfigLoader configLoader;
    private readonly IDevcontainerFeatureInitLinkSpecLoader linkSpecLoader;
    private readonly IDevcontainerFeatureInitLinkApplier linkApplier;

    public DevcontainerFeatureInitWorkflow(
        TextWriter stdout,
        TextWriter stderr,
        IDevcontainerProcessHelpers processHelpers,
        IDevcontainerUserEnvironmentSetup userEnvironmentSetup,
        IDevcontainerServiceBootstrap serviceBootstrap,
        IDevcontainerFeatureConfigLoader configLoader)
        : this(
            stdout,
            userEnvironmentSetup,
            serviceBootstrap,
            configLoader,
            new DevcontainerFeatureInitLinkSpecLoader(stderr),
            new DevcontainerFeatureInitLinkApplier(stdout, stderr, processHelpers))
    {
    }

    internal DevcontainerFeatureInitWorkflow(
        TextWriter stdout,
        IDevcontainerUserEnvironmentSetup userEnvironmentSetup,
        IDevcontainerServiceBootstrap serviceBootstrap,
        IDevcontainerFeatureConfigLoader configLoader,
        IDevcontainerFeatureInitLinkSpecLoader linkSpecLoader,
        IDevcontainerFeatureInitLinkApplier linkApplier)
    {
        this.stdout = stdout ?? throw new ArgumentNullException(nameof(stdout));
        this.userEnvironmentSetup = userEnvironmentSetup ?? throw new ArgumentNullException(nameof(userEnvironmentSetup));
        this.serviceBootstrap = serviceBootstrap ?? throw new ArgumentNullException(nameof(serviceBootstrap));
        this.configLoader = configLoader ?? throw new ArgumentNullException(nameof(configLoader));
        this.linkSpecLoader = linkSpecLoader ?? throw new ArgumentNullException(nameof(linkSpecLoader));
        this.linkApplier = linkApplier ?? throw new ArgumentNullException(nameof(linkApplier));
    }

}
