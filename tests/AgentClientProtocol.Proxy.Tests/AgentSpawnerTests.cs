using System.Diagnostics;
using AgentClientProtocol.Proxy.Sessions;
using Xunit;

namespace AgentClientProtocol.Proxy.Tests;

public sealed class AgentSpawnerTests
{
    [Fact]
    public void SpawnAgent_DirectSpawn_WithMissingBinary_ThrowsWithClearMessage()
    {
        using var session = new AcpSession("/tmp/workspace");
        var spawner = new AgentSpawner(directSpawn: true, TextWriter.Null);
        var missingAgent = $"containai-missing-{Guid.NewGuid():N}";

        var exception = Assert.Throws<InvalidOperationException>(() => spawner.SpawnAgent(session, missingAgent));

        Assert.Contains($"Agent '{missingAgent}' not found", exception.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void SpawnAgent_DirectSpawn_StartsProcess()
    {
        using var session = new AcpSession("/tmp/workspace");
        var stderr = new StringWriter();
        var spawner = new AgentSpawner(directSpawn: true, stderr);

        using var process = spawner.SpawnAgent(session, "sh");

        Assert.NotNull(process);
        Assert.True(process.WaitForExit(milliseconds: 5_000));
    }

    [Fact]
    public async Task SpawnAgent_ContainerMode_UsesCaiExecWrapperArguments()
    {
        using var temp = new TempDirectory();
        var fakeCaiPath = Path.Combine(temp.Path, "cai");
        var argsFile = Path.Combine(temp.Path, "args.log");
        var envFile = Path.Combine(temp.Path, "env.log");

        await File.WriteAllTextAsync(fakeCaiPath, $$"""
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$CAI_NO_UPDATE_CHECK" > "{{envFile}}"
printf '%s\n' "$@" > "{{argsFile}}"
while IFS= read -r _; do
  :
done
""", TestContext.Current.CancellationToken);
        EnsureExecutable(fakeCaiPath);

        using var session = new AcpSession("/tmp/workspace");
        var spawner = new AgentSpawner(directSpawn: false, TextWriter.Null, fakeCaiPath);
        using var process = spawner.SpawnAgent(session, "claude");

        await WaitForFileAsync(argsFile, TestContext.Current.CancellationToken);
        process.Kill(entireProcessTree: true);
        await process.WaitForExitAsync(TestContext.Current.CancellationToken);

        var args = await File.ReadAllLinesAsync(argsFile, TestContext.Current.CancellationToken);
        Assert.Equal("exec", args[0]);
        Assert.Equal("--workspace", args[1]);
        Assert.Equal("/tmp/workspace", args[2]);
        Assert.Equal("--quiet", args[3]);
        Assert.Equal("--", args[4]);
        Assert.Equal("bash", args[5]);
        Assert.Equal("-c", args[6]);
        Assert.Contains("command -v -- \"$1\"", args[7], StringComparison.Ordinal);
        Assert.Equal("--", args[8]);
        Assert.Equal("claude", args[9]);

        var env = await File.ReadAllTextAsync(envFile, TestContext.Current.CancellationToken);
        Assert.Contains("1", env, StringComparison.Ordinal);
    }

    private static async Task WaitForFileAsync(string path, CancellationToken cancellationToken)
    {
        if (File.Exists(path))
        {
            return;
        }

        var directory = Path.GetDirectoryName(path);
        var fileName = Path.GetFileName(path);
        if (string.IsNullOrWhiteSpace(directory))
        {
            throw new InvalidOperationException($"Unable to watch directory for path: {path}");
        }

        var fileCreated = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var watcher = new FileSystemWatcher(directory, fileName)
        {
            EnableRaisingEvents = true,
        };
        using var cancellation = cancellationToken.Register(
            static state => ((TaskCompletionSource)state!).TrySetCanceled(),
            fileCreated);

        watcher.Created += (_, _) => fileCreated.TrySetResult();
        watcher.Changed += (_, _) =>
        {
            if (File.Exists(path))
            {
                fileCreated.TrySetResult();
            }
        };

        if (File.Exists(path))
        {
            return;
        }

        await fileCreated.Task.WaitAsync(TimeSpan.FromSeconds(2), cancellationToken);
    }

    private static void EnsureExecutable(string path)
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        File.SetUnixFileMode(
            path,
            UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
    }

    private sealed class TempDirectory : IDisposable
    {
        public TempDirectory()
        {
            Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"agent-spawner-{Guid.NewGuid():N}");
            Directory.CreateDirectory(Path);
        }

        public string Path { get; }

        public void Dispose()
        {
            if (Directory.Exists(Path))
            {
                Directory.Delete(Path, recursive: true);
            }
        }
    }
}
