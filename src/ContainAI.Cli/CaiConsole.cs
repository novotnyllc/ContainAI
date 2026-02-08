using System.IO;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli;

internal sealed class CaiConsole : ICaiConsole
{
    public static ICaiConsole System { get; } = new CaiConsole(Console.Out, Console.Error);

    public CaiConsole(TextWriter output, TextWriter error)
    {
        StdOut = output ?? throw new ArgumentNullException(nameof(output));
        StdErr = error ?? throw new ArgumentNullException(nameof(error));
    }

    public TextWriter StdOut { get; }

    public TextWriter StdErr { get; }
}
