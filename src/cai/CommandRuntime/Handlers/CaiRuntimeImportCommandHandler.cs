using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiRuntimeImportCommandHandler
{
    private readonly CaiImportService importService;

    public CaiRuntimeImportCommandHandler(CaiImportService service)
        => importService = service ?? throw new ArgumentNullException(nameof(service));

    public Task<int> RunImportAsync(ImportCommandOptions options, CancellationToken cancellationToken)
        => importService.RunImportAsync(options, cancellationToken);
}
