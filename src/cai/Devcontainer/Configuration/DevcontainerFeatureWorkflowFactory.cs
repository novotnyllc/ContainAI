using ContainAI.Cli.Host.Devcontainer;
using ContainAI.Cli.Host.Devcontainer.InitLinks;
using ContainAI.Cli.Host.Devcontainer.Install;

namespace ContainAI.Cli.Host.Devcontainer.Configuration;

internal static class DevcontainerFeatureWorkflowFactory
{
    public static DevcontainerFeatureRuntimeWorkflows Create(
        TextWriter stdout,
        TextWriter stderr,
        IDevcontainerFeatureConfigService configService,
        IDevcontainerProcessHelpers processHelpers,
        IDevcontainerUserEnvironmentSetup userEnvironmentSetup,
        IDevcontainerServiceBootstrap serviceBootstrap,
        Func<string, string?> environmentVariableReader)
    {
        var settingsFactory = new DevcontainerFeatureSettingsFactory(configService, environmentVariableReader);
        var configLoader = new DevcontainerFeatureConfigLoader(configService, stderr);
        var installWorkflow = new DevcontainerFeatureInstallWorkflow(stdout, stderr, processHelpers, userEnvironmentSetup, settingsFactory);
        var initWorkflow = new DevcontainerFeatureInitWorkflow(stdout, stderr, processHelpers, userEnvironmentSetup, serviceBootstrap, configLoader);
        var startWorkflow = new DevcontainerFeatureStartWorkflow(stdout, stderr, serviceBootstrap, configLoader);
        return new DevcontainerFeatureRuntimeWorkflows(installWorkflow, initWorkflow, startWorkflow);
    }
}

internal readonly record struct DevcontainerFeatureRuntimeWorkflows(
    IDevcontainerFeatureInstallWorkflow InstallWorkflow,
    IDevcontainerFeatureInitWorkflow InitWorkflow,
    IDevcontainerFeatureStartWorkflow StartWorkflow);
