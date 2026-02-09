namespace ContainAI.Cli.Host;

internal sealed partial class InstallCommandRuntime
{
    private const string ContainAiDataHomeRelative = ".local/share/containai";
    private const string ContainAiBinHomeRelative = ".local/bin";

    private readonly TextWriter stderr;
    private readonly TextWriter stdout;

    public InstallCommandRuntime(
        TextWriter? standardOutput = null,
        TextWriter? standardError = null)
    {
        stdout = standardOutput ?? Console.Out;
        stderr = standardError ?? Console.Error;
    }
}
