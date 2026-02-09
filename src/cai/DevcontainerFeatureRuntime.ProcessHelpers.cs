namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerFeatureRuntime
{
    private sealed partial class DevcontainerProcessHelpers
    {
        private readonly DevcontainerFileSystem fileSystem;
        private readonly DevcontainerPortInspector portInspector;
        private readonly DevcontainerProcessCaptureRunner processCaptureRunner;

        public DevcontainerProcessHelpers()
        {
            fileSystem = new DevcontainerFileSystem();
            portInspector = new DevcontainerPortInspector();
            processCaptureRunner = new DevcontainerProcessCaptureRunner();
        }
    }

    private sealed class DevcontainerFileSystem
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

    private sealed class DevcontainerProcessCaptureRunner
    {
        private readonly Func<string, IReadOnlyList<string>, CancellationToken, Task<CliWrapProcessResult>> runCaptureAsync;

        public DevcontainerProcessCaptureRunner()
            => runCaptureAsync = (executable, arguments, cancellationToken) => CliWrapProcessRunner.RunCaptureAsync(executable, arguments, cancellationToken);

        public Task<CliWrapProcessResult> RunCaptureAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
            => runCaptureAsync(executable, arguments, cancellationToken);
    }

    private readonly record struct ProcessResult(int ExitCode, string StandardOutput, string StandardError);
}
