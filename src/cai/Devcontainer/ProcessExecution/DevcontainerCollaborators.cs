using System.Net.NetworkInformation;

namespace ContainAI.Cli.Host;

internal sealed class DevcontainerFileSystem
{
    private readonly Func<string, bool> fileExists;
    private readonly Func<string, bool> directoryExists;
    private readonly Func<string, FileAttributes> getAttributes;
    private readonly Func<string, CancellationToken, Task<string>> readAllTextAsync;
    private readonly Func<string, CancellationToken, Task<string[]>> readAllLinesAsync;

    public DevcontainerFileSystem()
    {
        fileExists = File.Exists;
        directoryExists = Directory.Exists;
        getAttributes = File.GetAttributes;
        readAllTextAsync = File.ReadAllTextAsync;
        readAllLinesAsync = File.ReadAllLinesAsync;
    }

    public bool FileExists(string path) => fileExists(path);

    public bool DirectoryExists(string path) => directoryExists(path);

    public FileAttributes GetAttributes(string path) => getAttributes(path);

    public Task<string> ReadAllTextAsync(string path, CancellationToken cancellationToken)
        => readAllTextAsync(path, cancellationToken);

    public Task<string[]> ReadAllLinesAsync(string path, CancellationToken cancellationToken)
        => readAllLinesAsync(path, cancellationToken);
}

internal sealed class DevcontainerProcessCaptureRunner
{
    private readonly Func<string, IReadOnlyList<string>, CancellationToken, Task<CliWrapProcessResult>> runCaptureAsync;

    public DevcontainerProcessCaptureRunner()
        => runCaptureAsync = (executable, arguments, cancellationToken) => CliWrapProcessRunner.RunCaptureAsync(executable, arguments, cancellationToken);

    public Task<CliWrapProcessResult> RunCaptureAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
        => runCaptureAsync(executable, arguments, cancellationToken);
}

internal sealed class DevcontainerPortInspector
{
    private readonly Func<IPGlobalProperties> ipGlobalPropertiesFactory;

    public DevcontainerPortInspector() => ipGlobalPropertiesFactory = IPGlobalProperties.GetIPGlobalProperties;

    public bool IsPortInUse(int port)
    {
        try
        {
            return ipGlobalPropertiesFactory()
                .GetActiveTcpListeners()
                .Any(endpoint => endpoint.Port == port);
        }
        catch (NetworkInformationException)
        {
            return false;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }
}
