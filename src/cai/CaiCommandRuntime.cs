using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiCommandRuntime : ICaiCommandRuntime
{
    private readonly AcpProxyRunner acpProxyRunner;
    private readonly SessionCommandRuntime sessionRuntime;
    private readonly CaiOperationsService operationsService;
    private readonly CaiConfigManifestService configManifestService;
    private readonly CaiImportService importService;
    private readonly ExamplesCommandRuntime examplesRuntime;
    private readonly InstallCommandRuntime installRuntime;

    // Exposed for tests via reflection-backed console bridge.
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;

    public CaiCommandRuntime(TextWriter? standardOutput = null, TextWriter? standardError = null)
        : this(new AcpProxyRunner(), standardOutput, standardError)
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
    {
        ArgumentNullException.ThrowIfNull(proxyRunner);
        ArgumentNullException.ThrowIfNull(manifestTomlParser);

        acpProxyRunner = proxyRunner;
        stdout = standardOutput ?? Console.Out;
        stderr = standardError ?? Console.Error;

        sessionRuntime = new SessionCommandRuntime(stdout, stderr);
        operationsService = new CaiOperationsService(stdout, stderr, manifestTomlParser);
        configManifestService = new CaiConfigManifestService(stdout, stderr, manifestTomlParser);
        importService = new CaiImportService(stdout, stderr, manifestTomlParser);
        installRuntime = new InstallCommandRuntime();
        examplesRuntime = new ExamplesCommandRuntime();
    }
}
