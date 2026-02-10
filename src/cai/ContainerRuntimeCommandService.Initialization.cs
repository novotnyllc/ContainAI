using System.Security.Cryptography;
using System.Text;
using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;
using ContainAI.Cli.Host.ContainerRuntime.Services;
using ContainAI.Cli.Host;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal interface IContainerRuntimeInitializationWorkflow
{
    Task RunAsync(InitCommandParsing options, CancellationToken cancellationToken);
}

internal sealed class ContainerRuntimeInitializationWorkflow : IContainerRuntimeInitializationWorkflow
{
    private readonly IContainerRuntimeExecutionContext context;
    private readonly IContainerRuntimeEnvironmentFileLoader envFileLoader;
    private readonly IContainerRuntimeGitConfigService gitConfigService;
    private readonly IContainerRuntimeWorkspaceLinkService workspaceLinkService;
    private readonly IContainerRuntimeManifestBootstrapService manifestBootstrapService;

    public ContainerRuntimeInitializationWorkflow(
        IContainerRuntimeExecutionContext context,
        IContainerRuntimeEnvironmentFileLoader envFileLoader,
        IContainerRuntimeGitConfigService gitConfigService,
        IContainerRuntimeWorkspaceLinkService workspaceLinkService,
        IContainerRuntimeManifestBootstrapService manifestBootstrapService)
    {
        this.context = context ?? throw new ArgumentNullException(nameof(context));
        this.envFileLoader = envFileLoader ?? throw new ArgumentNullException(nameof(envFileLoader));
        this.gitConfigService = gitConfigService ?? throw new ArgumentNullException(nameof(gitConfigService));
        this.workspaceLinkService = workspaceLinkService ?? throw new ArgumentNullException(nameof(workspaceLinkService));
        this.manifestBootstrapService = manifestBootstrapService ?? throw new ArgumentNullException(nameof(manifestBootstrapService));
    }

    public async Task RunAsync(InitCommandParsing options, CancellationToken cancellationToken)
    {
        await context.LogInfoAsync(options.Quiet, "ContainAI initialization starting...").ConfigureAwait(false);

        await UpdateAgentPasswordAsync().ConfigureAwait(false);
        await manifestBootstrapService.EnsureVolumeStructureAsync(options.DataDir, options.ManifestsDir, options.Quiet).ConfigureAwait(false);
        await envFileLoader.LoadEnvFileAsync(Path.Combine(options.DataDir, ".env"), options.Quiet).ConfigureAwait(false);
        await gitConfigService.MigrateGitConfigAsync(options.DataDir, options.Quiet).ConfigureAwait(false);
        await gitConfigService.SetupGitConfigAsync(options.DataDir, options.HomeDir, options.Quiet).ConfigureAwait(false);
        await workspaceLinkService.SetupWorkspaceSymlinkAsync(options.WorkspaceDir, options.Quiet).ConfigureAwait(false);
        await manifestBootstrapService.ProcessUserManifestsAsync(options.DataDir, options.HomeDir, options.Quiet).ConfigureAwait(false);

        await manifestBootstrapService.RunHooksAsync(options.TemplateHooksDir, options.WorkspaceDir, options.HomeDir, options.Quiet, cancellationToken).ConfigureAwait(false);
        await manifestBootstrapService.RunHooksAsync(options.WorkspaceHooksDir, options.WorkspaceDir, options.HomeDir, options.Quiet, cancellationToken).ConfigureAwait(false);

        await context.LogInfoAsync(options.Quiet, "ContainAI initialization complete").ConfigureAwait(false);
    }

    private async Task UpdateAgentPasswordAsync()
    {
        const string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
        Span<byte> randomBytes = stackalloc byte[32];
        RandomNumberGenerator.Fill(randomBytes);
        var builder = new StringBuilder(capacity: randomBytes.Length);
        foreach (var b in randomBytes)
        {
            builder.Append(alphabet[b % alphabet.Length]);
        }

        var payload = $"agent:{builder}\n";
        _ = await context.RunAsRootCaptureAsync("chpasswd", [], payload, CancellationToken.None).ConfigureAwait(false);
    }
}
