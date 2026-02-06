namespace ContainAI.Cli.Abstractions;

public interface ILegacyContainAiBridge
{
    Task<int> InvokeAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);
}
