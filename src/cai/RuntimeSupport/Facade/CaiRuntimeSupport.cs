using ContainAI.Cli.Host.RuntimeSupport.Models;

namespace ContainAI.Cli.Host;

internal abstract partial class CaiRuntimeSupport
{
    protected readonly TextWriter stdout;
    protected readonly TextWriter stderr;

    protected static readonly string[] ConfigFileNames =
    [
        "config.toml",
        "containai.toml",
    ];

    protected CaiRuntimeSupport(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput;
        stderr = standardError;
    }

    private static ProcessResult ToProcessResult(RuntimeProcessResult result)
        => new(result.ExitCode, result.StandardOutput, result.StandardError);
}
