namespace ContainAI.Cli.Host;

internal sealed partial class ExamplesCommandRuntime
{
    private readonly IExamplesDictionaryProvider dictionaryProvider;
    private readonly TextWriter stderr;
    private readonly TextWriter stdout;

    public ExamplesCommandRuntime(
        IExamplesDictionaryProvider? dictionaryProvider = null,
        TextWriter? standardOutput = null,
        TextWriter? standardError = null)
    {
        this.dictionaryProvider = dictionaryProvider ?? new ExamplesStaticDictionaryProvider();
        stdout = standardOutput ?? Console.Out;
        stderr = standardError ?? Console.Error;
    }
}
