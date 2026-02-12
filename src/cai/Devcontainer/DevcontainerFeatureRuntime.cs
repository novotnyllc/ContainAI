using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.Devcontainer.Configuration;

namespace ContainAI.Cli.Host.Devcontainer;

internal sealed class DevcontainerFeatureRuntime
{
    private readonly TextWriter stderr;
    private readonly IDevcontainerFeatureInstallWorkflow installWorkflow;
    private readonly IDevcontainerFeatureInitWorkflow initWorkflow;
    private readonly IDevcontainerFeatureStartWorkflow startWorkflow;

    public DevcontainerFeatureRuntime(TextWriter standardOutput, TextWriter standardError)
    {
        var configService = new DevcontainerFeatureConfigService();
        var processHelpers = new DevcontainerProcessHelpers();
        Func<string, string?> environmentVariableReader = Environment.GetEnvironmentVariable;
        var userEnvironmentSetup = new DevcontainerUserEnvironmentSetup(processHelpers, standardOutput, environmentVariableReader);
        var serviceBootstrap = new DevcontainerServiceBootstrap(processHelpers, standardOutput, standardError, environmentVariableReader);
        var output = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        var error = standardError ?? throw new ArgumentNullException(nameof(standardError));

        var workflows = DevcontainerFeatureWorkflowFactory.Create(
            output,
            error,
            configService,
            processHelpers,
            userEnvironmentSetup,
            serviceBootstrap,
            environmentVariableReader);
        stderr = error;
        installWorkflow = workflows.InstallWorkflow;
        initWorkflow = workflows.InitWorkflow;
        startWorkflow = workflows.StartWorkflow;
    }

    internal DevcontainerFeatureRuntime(
        TextWriter standardOutput,
        TextWriter standardError,
        IDevcontainerFeatureInstallWorkflow installWorkflow,
        IDevcontainerFeatureInitWorkflow initWorkflow,
        IDevcontainerFeatureStartWorkflow startWorkflow)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        this.installWorkflow = installWorkflow ?? throw new ArgumentNullException(nameof(installWorkflow));
        this.initWorkflow = initWorkflow ?? throw new ArgumentNullException(nameof(initWorkflow));
        this.startWorkflow = startWorkflow ?? throw new ArgumentNullException(nameof(startWorkflow));
    }

    public async Task<int> RunDevcontainerAsync(CancellationToken cancellationToken)
    {
        _ = cancellationToken;
        await stderr.WriteLineAsync("Usage: cai system devcontainer <install|init|start|verify-sysbox>").ConfigureAwait(false);
        return 1;
    }

    public Task<int> RunInstallAsync(SystemDevcontainerInstallCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return installWorkflow.RunInstallAsync(options, cancellationToken);
    }

    public Task<int> RunInitAsync(CancellationToken cancellationToken)
        => initWorkflow.RunInitAsync(cancellationToken);

    public Task<int> RunStartAsync(CancellationToken cancellationToken)
        => startWorkflow.RunStartAsync(cancellationToken);

    public Task<int> RunVerifySysboxAsync(CancellationToken cancellationToken)
        => startWorkflow.RunVerifySysboxAsync(cancellationToken);
}
