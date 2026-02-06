using System.Text.Json;
using ContainAI.Cli.Host;
using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class WorkspaceStateTests
{
    [Fact]
    public void WriteAndReadWorkspaceState_RoundTripsValues()
    {
        using var temp = new TemporaryDirectory();
        var configPath = Path.Combine(temp.Path, "config", "containai", "config.toml");

        var setVolume = TomlCommandProcessor.Execute([
            "--file", configPath,
            "--set-workspace-key", "/tmp/test-workspace", "data_volume", "test-vol",
        ]);
        Assert.Equal(0, setVolume.ExitCode);

        var setContainer = TomlCommandProcessor.Execute([
            "--file", configPath,
            "--set-workspace-key", "/tmp/test-workspace", "container_name", "my-container",
        ]);
        Assert.Equal(0, setContainer.ExitCode);

        var getWorkspace = TomlCommandProcessor.Execute([
            "--file", configPath,
            "--get-workspace", "/tmp/test-workspace",
        ]);

        Assert.Equal(0, getWorkspace.ExitCode);
        using var json = JsonDocument.Parse(getWorkspace.StandardOutput);
        Assert.Equal("test-vol", json.RootElement.GetProperty("data_volume").GetString());
        Assert.Equal("my-container", json.RootElement.GetProperty("container_name").GetString());
    }

    [Fact]
    public void SetWorkspaceKey_RejectsRelativePath()
    {
        using var temp = new TemporaryDirectory();
        var configPath = Path.Combine(temp.Path, "config", "containai", "config.toml");

        var result = TomlCommandProcessor.Execute([
            "--file", configPath,
            "--set-workspace-key", "relative/path", "k", "v",
        ]);

        Assert.Equal(1, result.ExitCode);
        Assert.Contains("Workspace path must be absolute", result.StandardError, StringComparison.Ordinal);
    }

    [Fact]
    public void UnsetWorkspaceKey_RemovesEntry()
    {
        using var temp = new TemporaryDirectory();
        var configPath = Path.Combine(temp.Path, "config", "containai", "config.toml");

        var set = TomlCommandProcessor.Execute([
            "--file", configPath,
            "--set-workspace-key", "/tmp/test-workspace", "agent", "codex",
        ]);
        Assert.Equal(0, set.ExitCode);

        var unset = TomlCommandProcessor.Execute([
            "--file", configPath,
            "--unset-workspace-key", "/tmp/test-workspace", "agent",
        ]);
        Assert.Equal(0, unset.ExitCode);

        var get = TomlCommandProcessor.Execute([
            "--file", configPath,
            "--get-workspace", "/tmp/test-workspace",
        ]);
        Assert.Equal(0, get.ExitCode);

        using var json = JsonDocument.Parse(get.StandardOutput);
        Assert.Equal(JsonValueKind.Object, json.RootElement.ValueKind);
        Assert.False(json.RootElement.TryGetProperty("agent", out _));
    }

    [Fact]
    public void SetAndUnsetGlobalKey_Works()
    {
        using var temp = new TemporaryDirectory();
        var configPath = Path.Combine(temp.Path, "config", "containai", "config.toml");

        var set = TomlCommandProcessor.Execute([
            "--file", configPath,
            "--set-key", "agent.data_volume", "containai-data",
        ]);
        Assert.Equal(0, set.ExitCode);

        var get = TomlCommandProcessor.Execute([
            "--file", configPath,
            "--key", "agent.data_volume",
        ]);
        Assert.Equal(0, get.ExitCode);
        Assert.Equal("containai-data", get.StandardOutput);

        var unset = TomlCommandProcessor.Execute([
            "--file", configPath,
            "--unset-key", "agent.data_volume",
        ]);
        Assert.Equal(0, unset.ExitCode);

        var getAfter = TomlCommandProcessor.Execute([
            "--file", configPath,
            "--key", "agent.data_volume",
        ]);
        Assert.Equal(0, getAfter.ExitCode);
        Assert.Equal(string.Empty, getAfter.StandardOutput);
    }

    [Fact]
    public void SetWorkspaceState_CreatesSecurePermissions_OnUnix()
    {
        if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
        {
            return;
        }

        using var temp = new TemporaryDirectory();
        var configPath = Path.Combine(temp.Path, "config", "containai", "config.toml");

        var set = TomlCommandProcessor.Execute([
            "--file", configPath,
            "--set-workspace-key", "/tmp/test-workspace", "k", "v",
        ]);

        Assert.Equal(0, set.ExitCode);

        var configDir = Path.GetDirectoryName(configPath)!;
        var dirMode = File.GetUnixFileMode(configDir);
        var fileMode = File.GetUnixFileMode(configPath);

        Assert.Equal(
            UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute,
            dirMode);
        Assert.Equal(
            UnixFileMode.UserRead | UnixFileMode.UserWrite,
            fileMode);
    }

    private sealed class TemporaryDirectory : IDisposable
    {
        public TemporaryDirectory()
        {
            Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"cai-ws-{Guid.NewGuid():N}");
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
