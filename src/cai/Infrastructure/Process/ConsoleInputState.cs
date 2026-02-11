namespace ContainAI.Cli.Host;

internal interface IConsoleInputState
{
    bool IsInputRedirected { get; }
}

internal sealed class ConsoleInputState : IConsoleInputState
{
    public static ConsoleInputState Instance { get; } = new();

    public bool IsInputRedirected => Console.IsInputRedirected;
}
