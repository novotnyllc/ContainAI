using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal interface IInstallCommandExecution
{
    Task<int> RunAsync(InstallCommandOptions options, CancellationToken cancellationToken);
}

internal sealed class InstallCommandExecution : IInstallCommandExecution
{
    private readonly IInstallCommandOutput output;
    private readonly InstallCommandContextResolver contextResolver;
    private readonly InstallFlowExecutor flowExecutor;

    public InstallCommandExecution(
        IInstallPathResolver pathResolver,
        IInstallDeploymentService deploymentService,
        IInstallAssetMaterializer assetMaterializer,
        IInstallCommandOutput output,
        IInstallShellIntegrationUpdater shellIntegrationUpdater,
        IInstallSetupRunner setupRunner)
    {
        ArgumentNullException.ThrowIfNull(pathResolver);
        ArgumentNullException.ThrowIfNull(deploymentService);
        ArgumentNullException.ThrowIfNull(assetMaterializer);
        this.output = output ?? throw new ArgumentNullException(nameof(output));
        ArgumentNullException.ThrowIfNull(shellIntegrationUpdater);
        ArgumentNullException.ThrowIfNull(setupRunner);

        contextResolver = new InstallCommandContextResolver(pathResolver, this.output);
        flowExecutor = new InstallFlowExecutor(
            deploymentService,
            assetMaterializer,
            this.output,
            shellIntegrationUpdater,
            setupRunner);
    }

    public async Task<int> RunAsync(InstallCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);

        var resolution = await contextResolver.ResolveAsync(options, cancellationToken).ConfigureAwait(false);
        if (!resolution.Success)
        {
            return 1;
        }

        try
        {
            return await flowExecutor.ExecuteAsync(resolution.Context!.Value, cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (IOException ex)
        {
            return await InstallCommandErrorHandler.WriteErrorAndReturnAsync(output, ex.Message, cancellationToken).ConfigureAwait(false);
        }
        catch (UnauthorizedAccessException ex)
        {
            return await InstallCommandErrorHandler.WriteErrorAndReturnAsync(output, ex.Message, cancellationToken).ConfigureAwait(false);
        }
        catch (ArgumentException ex)
        {
            return await InstallCommandErrorHandler.WriteErrorAndReturnAsync(output, ex.Message, cancellationToken).ConfigureAwait(false);
        }
        catch (NotSupportedException ex)
        {
            return await InstallCommandErrorHandler.WriteErrorAndReturnAsync(output, ex.Message, cancellationToken).ConfigureAwait(false);
        }
        catch (InvalidOperationException ex)
        {
            return await InstallCommandErrorHandler.WriteErrorAndReturnAsync(output, ex.Message, cancellationToken).ConfigureAwait(false);
        }
    }
}
