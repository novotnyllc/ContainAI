namespace ContainAI.Cli.Host;

internal interface ICaiRefreshOperations
{
    Task<int> RunRefreshAsync(bool rebuild, bool showHelp, CancellationToken cancellationToken);
}

internal sealed class CaiRefreshOperations : ICaiRefreshOperations
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly ICaiBaseImageResolver baseImageResolver;
    private readonly ICaiDockerImagePuller imagePuller;
    private readonly ICaiTemplateRebuilder templateRebuilder;

    public CaiRefreshOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        ICaiBaseImageResolver caiBaseImageResolver,
        ICaiDockerImagePuller caiDockerImagePuller,
        ICaiTemplateRebuilder caiTemplateRebuilder)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        baseImageResolver = caiBaseImageResolver ?? throw new ArgumentNullException(nameof(caiBaseImageResolver));
        imagePuller = caiDockerImagePuller ?? throw new ArgumentNullException(nameof(caiDockerImagePuller));
        templateRebuilder = caiTemplateRebuilder ?? throw new ArgumentNullException(nameof(caiTemplateRebuilder));
    }

    public async Task<int> RunRefreshAsync(bool rebuild, bool showHelp, CancellationToken cancellationToken)
    {
        if (showHelp)
        {
            await stdout.WriteLineAsync("Usage: cai refresh [--rebuild] [--verbose]").ConfigureAwait(false);
            return 0;
        }

        var baseImage = await baseImageResolver.ResolveBaseImageAsync(cancellationToken).ConfigureAwait(false);
        await stdout.WriteLineAsync($"Pulling {baseImage}...").ConfigureAwait(false);

        var pull = await imagePuller.PullAsync(baseImage, cancellationToken).ConfigureAwait(false);
        if (pull.ExitCode != 0)
        {
            await stderr.WriteLineAsync(pull.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        if (!rebuild)
        {
            await stdout.WriteLineAsync("Refresh complete.").ConfigureAwait(false);
            return 0;
        }

        return await templateRebuilder.RebuildTemplatesAsync(baseImage, cancellationToken).ConfigureAwait(false);
    }
}
