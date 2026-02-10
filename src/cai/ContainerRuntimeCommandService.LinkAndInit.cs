using System.Security.Cryptography;
using System.Text;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeCommandService
{
    private async Task UpdateAgentPasswordAsync()
    {
        const string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
        Span<byte> randomBytes = stackalloc byte[32];
        RandomNumberGenerator.Fill(randomBytes);
        var builder = new StringBuilder(capacity: randomBytes.Length);
        foreach (var b in randomBytes)
        {
            builder.Append(alphabet[b % alphabet.Length]);
        }

        var payload = $"agent:{builder}\n";
        _ = await RunAsRootCaptureAsync("chpasswd", [], payload, CancellationToken.None).ConfigureAwait(false);
    }

    private static async Task<bool> IsSymlinkAsync(string path)
    {
        var result = await RunProcessCaptureAsync("test", ["-L", path], null, CancellationToken.None).ConfigureAwait(false);
        return result.ExitCode == 0;
    }

    private static async Task<string?> ReadLinkTargetAsync(string path)
    {
        var result = await RunProcessCaptureAsync("readlink", [path], null, CancellationToken.None).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            return null;
        }

        return result.StandardOutput.Trim();
    }

    private static async Task<string?> TryReadTrimmedTextAsync(string path)
    {
        try
        {
            return (await File.ReadAllTextAsync(path).ConfigureAwait(false)).Trim();
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
    }

    private static void EnsureFileWithContent(string path, string? content)
    {
        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        if (!File.Exists(path))
        {
            using (File.Create(path))
            {
            }
        }

        if (content is not null && new FileInfo(path).Length == 0)
        {
            File.WriteAllText(path, content);
        }
    }

    private static async Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments) => _ = await RunAsRootCaptureAsync(executable, arguments, null, CancellationToken.None).ConfigureAwait(false);

    private static async Task<ProcessCaptureResult> RunAsRootCaptureAsync(
        string executable,
        IReadOnlyList<string> arguments,
        string? standardInput,
        CancellationToken cancellationToken)
    {
        if (IsRunningAsRoot())
        {
            var direct = await RunProcessCaptureAsync(executable, arguments, null, cancellationToken, standardInput).ConfigureAwait(false);
            if (direct.ExitCode != 0)
            {
                throw new InvalidOperationException($"Command failed: {executable} {string.Join(' ', arguments)}: {direct.StandardError.Trim()}");
            }

            return direct;
        }

        var sudoArguments = new List<string>(capacity: arguments.Count + 2)
        {
            "-n",
            executable,
        };
        foreach (var argument in arguments)
        {
            sudoArguments.Add(argument);
        }

        var sudo = await RunProcessCaptureAsync("sudo", sudoArguments, null, cancellationToken, standardInput).ConfigureAwait(false);
        if (sudo.ExitCode != 0)
        {
            throw new InvalidOperationException($"sudo command failed for {executable}: {sudo.StandardError.Trim()}");
        }

        return sudo;
    }

    private static bool IsRunningAsRoot()
    {
        try
        {
            return string.Equals(Environment.UserName, "root", StringComparison.Ordinal);
        }
        catch (InvalidOperationException)
        {
            return false;
        }
        catch (PlatformNotSupportedException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }
    }

    private async Task LogInfoAsync(bool quiet, string message)
    {
        if (quiet)
        {
            return;
        }

        await stdout.WriteLineAsync($"[INFO] {message}").ConfigureAwait(false);
    }

    private static async Task WriteTimestampAsync(string path)
    {
        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var temporaryPath = $"{path}.tmp.{Environment.ProcessId}";
        var timestamp = DateTimeOffset.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", System.Globalization.CultureInfo.InvariantCulture) + Environment.NewLine;
        await File.WriteAllTextAsync(temporaryPath, timestamp).ConfigureAwait(false);
        File.Move(temporaryPath, path, overwrite: true);
    }

    private static async Task<ProcessCaptureResult> RunProcessCaptureAsync(
        string executable,
        IReadOnlyList<string> arguments,
        string? workingDirectory,
        CancellationToken cancellationToken,
        string? standardInput = null)
    {
        var result = await CliWrapProcessRunner
            .RunCaptureAsync(executable, arguments, cancellationToken, workingDirectory, standardInput)
            .ConfigureAwait(false);

        return new ProcessCaptureResult(result.ExitCode, result.StandardOutput, result.StandardError);
    }

    private sealed class LinkRepairStats
    {
        public int Broken { get; set; }

        public int Missing { get; set; }

        public int Ok { get; set; }

        public int Fixed { get; set; }

        public int Errors { get; set; }
    }

    private sealed record ProcessCaptureResult(int ExitCode, string StandardOutput, string StandardError);
}
