using System.IO;

namespace ContainAI.Cli.Abstractions;

public interface ICaiConsole
{
    TextWriter OutputWriter { get; }

    TextWriter ErrorWriter { get; }
}
