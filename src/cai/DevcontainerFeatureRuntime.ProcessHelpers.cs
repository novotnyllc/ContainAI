using System.Net.NetworkInformation;

namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerFeatureRuntime
{
    private sealed class DevcontainerProcessHelpers
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

        public bool IsSymlink(string path)
        {
            try
            {
                var attributes = fileSystem.GetAttributes(path);
                return (attributes & FileAttributes.ReparsePoint) != 0;
            }
            catch (IOException)
            {
                return false;
            }
            catch (UnauthorizedAccessException)
            {
                return false;
            }
            catch (ArgumentException)
            {
                return false;
            }
            catch (NotSupportedException)
            {
                return false;
            }
        }

        public bool IsProcessAlive(int processId)
        {
            if (processId <= 0)
            {
                return false;
            }

            try
            {
                if (OperatingSystem.IsLinux() && fileSystem.DirectoryExists($"/proc/{processId}"))
                {
                    return true;
                }

                if (OperatingSystem.IsLinux() || OperatingSystem.IsMacOS())
                {
                    var result = processCaptureRunner
                        .RunCaptureAsync("kill", ["-0", processId.ToString(System.Globalization.CultureInfo.InvariantCulture)], CancellationToken.None)
                        .GetAwaiter()
                        .GetResult();
                    return result.ExitCode == 0;
                }
            }
            catch (InvalidOperationException)
            {
                return false;
            }
            catch (IOException)
            {
                return false;
            }
            catch (NotSupportedException)
            {
                return false;
            }

            return false;
        }

        public bool IsPortInUse(string portValue)
        {
            if (!int.TryParse(portValue, out var port))
            {
                return false;
            }

            return portInspector.IsPortInUse(port);
        }

        public async Task<bool> IsSshdRunningFromPidFileAsync(string pidFilePath, CancellationToken cancellationToken)
        {
            if (!fileSystem.FileExists(pidFilePath))
            {
                return false;
            }

            var pidRaw = await fileSystem.ReadAllTextAsync(pidFilePath, cancellationToken).ConfigureAwait(false);
            if (!int.TryParse(pidRaw.Trim(), out var pid))
            {
                return false;
            }

            if (!fileSystem.DirectoryExists($"/proc/{pid}"))
            {
                return false;
            }

            var commPath = $"/proc/{pid}/comm";
            if (fileSystem.FileExists(commPath))
            {
                var comm = (await fileSystem.ReadAllTextAsync(commPath, cancellationToken).ConfigureAwait(false)).Trim();
                return string.Equals(comm, "sshd", StringComparison.Ordinal);
            }

            return IsProcessAlive(pid);
        }

        public async Task<bool> IsSysboxFsMountedAsync(CancellationToken cancellationToken)
        {
            if (!fileSystem.FileExists("/proc/mounts"))
            {
                return false;
            }

            var mounts = await fileSystem.ReadAllLinesAsync("/proc/mounts", cancellationToken).ConfigureAwait(false);
            foreach (var line in mounts)
            {
                var fields = line.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                if (fields.Length >= 3 &&
                    (string.Equals(fields[2], "sysboxfs", StringComparison.Ordinal) ||
                     string.Equals(fields[2], "fuse.sysboxfs", StringComparison.Ordinal)))
                {
                    return true;
                }
            }

            return false;
        }

        public async Task<bool> HasUidMappingIsolationAsync(CancellationToken cancellationToken)
        {
            if (!fileSystem.FileExists("/proc/self/uid_map"))
            {
                return false;
            }

            var lines = await fileSystem.ReadAllLinesAsync("/proc/self/uid_map", cancellationToken).ConfigureAwait(false);
            foreach (var line in lines)
            {
                var fields = line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
                if (fields.Length >= 3 && fields[0] == "0")
                {
                    return fields[1] != "0";
                }
            }

            return false;
        }

        public async Task<bool> CommandExistsAsync(string command, CancellationToken cancellationToken)
        {
            var result = await RunProcessCaptureAsync("sh", ["-c", $"command -v {command} >/dev/null 2>&1"], cancellationToken).ConfigureAwait(false);
            return result.ExitCode == 0;
        }

        public async Task<bool> CommandSucceedsAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
        {
            var result = await RunProcessCaptureAsync(executable, arguments, cancellationToken).ConfigureAwait(false);
            return result.ExitCode == 0;
        }

        public async Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
        {
            if (IsRunningAsRoot())
            {
                var direct = await RunProcessCaptureAsync(executable, arguments, cancellationToken).ConfigureAwait(false);
                if (direct.ExitCode != 0)
                {
                    throw new InvalidOperationException(direct.StandardError.Trim());
                }

                return;
            }

            if (!await CommandSucceedsAsync("sudo", ["-n", "true"], cancellationToken).ConfigureAwait(false))
            {
                throw new InvalidOperationException($"Root privileges required for command: {executable}");
            }

            var sudoArgs = new List<string>(arguments.Count + 2) { "-n", executable };
            foreach (var argument in arguments)
            {
                sudoArgs.Add(argument);
            }

            var sudoResult = await RunProcessCaptureAsync("sudo", sudoArgs, cancellationToken).ConfigureAwait(false);
            if (sudoResult.ExitCode != 0)
            {
                throw new InvalidOperationException(sudoResult.StandardError.Trim());
            }
        }

        public async Task<ProcessResult> RunProcessCaptureAsync(string executable, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
        {
            var result = await processCaptureRunner.RunCaptureAsync(executable, arguments, cancellationToken).ConfigureAwait(false);
            return new ProcessResult(result.ExitCode, result.StandardOutput, result.StandardError);
        }

        private static bool IsRunningAsRoot() => string.Equals(Environment.UserName, "root", StringComparison.Ordinal);
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

    private sealed class DevcontainerPortInspector
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
