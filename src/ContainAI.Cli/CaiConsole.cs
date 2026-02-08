using System.IO;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli;

internal sealed class CaiConsole : ICaiConsole
{
    public static ICaiConsole System => new CaiConsole(Console.Out, Console.Error);

    public CaiConsole(TextWriter output, TextWriter error)
    {
        OutputWriter = output ?? throw new ArgumentNullException(nameof(output));
        ErrorWriter = error ?? throw new ArgumentNullException(nameof(error));
    }

    public TextWriter OutputWriter { get; }

    public TextWriter ErrorWriter { get; }
}
