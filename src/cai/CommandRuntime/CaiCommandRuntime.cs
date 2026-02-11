using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiCommandRuntime : CaiCommandRuntimeDispatchBase
{
    // Exposed for tests via reflection-backed console bridge.
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;

    public CaiCommandRuntime(TextWriter? standardOutput = null, TextWriter? standardError = null)
        : this(new AcpProxyRunner(), new ManifestTomlParser(), standardOutput, standardError)
    {
    }

    public CaiCommandRuntime(
        AcpProxyRunner proxyRunner,
        TextWriter? standardOutput = null,
        TextWriter? standardError = null)
        : this(proxyRunner, new ManifestTomlParser(), standardOutput, standardError)
    {
    }

    internal CaiCommandRuntime(
        AcpProxyRunner proxyRunner,
        IManifestTomlParser manifestTomlParser,
        TextWriter? standardOutput = null,
        TextWriter? standardError = null)
        : this(CreateRuntimeState(proxyRunner, manifestTomlParser, standardOutput, standardError))
    {
    }

    private CaiCommandRuntime((CaiCommandRuntimeHandlers Handlers, TextWriter Stdout, TextWriter Stderr) runtimeState)
        : base(runtimeState.Handlers)
    {
        stdout = runtimeState.Stdout;
        stderr = runtimeState.Stderr;
    }

    private static (CaiCommandRuntimeHandlers Handlers, TextWriter Stdout, TextWriter Stderr) CreateRuntimeState(
        AcpProxyRunner proxyRunner,
        IManifestTomlParser manifestTomlParser,
        TextWriter? standardOutput,
        TextWriter? standardError)
    {
        ArgumentNullException.ThrowIfNull(proxyRunner);
        ArgumentNullException.ThrowIfNull(manifestTomlParser);

        var stdout = standardOutput ?? Console.Out;
        var stderr = standardError ?? Console.Error;
        var handlers = CaiCommandRuntimeHandlersFactory.Create(proxyRunner, manifestTomlParser, stdout, stderr);
        return (handlers, stdout, stderr);
    }
}
