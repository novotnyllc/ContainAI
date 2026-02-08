using System.IO;

namespace ContainAI.Cli.Abstractions;

public interface ICaiConsole
{
    TextWriter StdOut { get; }

    TextWriter StdErr { get; }
}
