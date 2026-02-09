namespace ContainAI.Cli.Host;

internal abstract partial class CaiRuntimeSupport
{
    protected readonly TextWriter stdout;
    protected readonly TextWriter stderr;

    protected CaiRuntimeSupport(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput;
        stderr = standardError;
    }
}
