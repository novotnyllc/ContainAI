namespace ContainAI.Cli.Host;

internal sealed class ConsoleInputState : IConsoleInputState
{
    public static ConsoleInputState Instance { get; } = new();

    public bool IsInputRedirected => Console.IsInputRedirected;
}
