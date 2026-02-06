using System.Text.Json;
using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class WorkspaceStateTests
{
    [Fact]
    public async Task UserConfigPath_UsesXdgConfigHome()
    {
        using var temp = ShellTestSupport.CreateTemporaryDirectory("cai-ws-xdg");
        var xdgPath = Path.Combine(temp.Path, "config");
        var cancellationToken = TestContext.Current.CancellationToken;
        var corePath = Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/core.sh");
        var platformPath = Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/platform.sh");
        var configPath = Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/config.sh");

        var result = await ShellTestSupport.RunBashAsync(
            $"""
            source {ShellTestSupport.ShellQuote(corePath)}
            source {ShellTestSupport.ShellQuote(platformPath)}
            source {ShellTestSupport.ShellQuote(configPath)}
            _containai_user_config_path
            """,
            environment: new Dictionary<string, string?> { ["XDG_CONFIG_HOME"] = xdgPath },
            cancellationToken: cancellationToken);

        Assert.Equal(0, result.ExitCode);
        Assert.Equal(Path.Combine(xdgPath, "containai/config.toml"), result.StdOut.Trim());
    }

    [Fact]
    public async Task WriteWorkspaceState_CreatesExpectedPermissions()
    {
        using var temp = ShellTestSupport.CreateTemporaryDirectory("cai-ws-perms");
        var xdgPath = Path.Combine(temp.Path, "config");
        var cancellationToken = TestContext.Current.CancellationToken;
        var corePath = Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/core.sh");
        var platformPath = Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/platform.sh");
        var configPath = Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/config.sh");

        var result = await ShellTestSupport.RunBashAsync(
            $"""
            source {ShellTestSupport.ShellQuote(corePath)}
            source {ShellTestSupport.ShellQuote(platformPath)}
            source {ShellTestSupport.ShellQuote(configPath)}

            _containai_write_workspace_state "/tmp/test-workspace" "data_volume" "test-vol"

            dir_perms=$(stat -c '%a' "{xdgPath}/containai" 2>/dev/null || stat -f '%Lp' "{xdgPath}/containai")
            file_perms=$(stat -c '%a' "{xdgPath}/containai/config.toml" 2>/dev/null || stat -f '%Lp' "{xdgPath}/containai/config.toml")
            printf '%s|%s' "$dir_perms" "$file_perms"
            """,
            environment: new Dictionary<string, string?> { ["XDG_CONFIG_HOME"] = xdgPath },
            cancellationToken: cancellationToken);

        Assert.Equal(0, result.ExitCode);
        var split = result.StdOut.Trim().Split('|', StringSplitOptions.RemoveEmptyEntries);
        Assert.Equal("700", split[0]);
        Assert.Equal("600", split[1]);
    }

    [Fact]
    public async Task ReadAndWriteWorkspaceState_RoundTripsValues()
    {
        using var temp = ShellTestSupport.CreateTemporaryDirectory("cai-ws-roundtrip");
        var xdgPath = Path.Combine(temp.Path, "config");
        var cancellationToken = TestContext.Current.CancellationToken;
        var corePath = Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/core.sh");
        var platformPath = Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/platform.sh");
        var configPath = Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/config.sh");

        var result = await ShellTestSupport.RunBashAsync(
            $"""
            source {ShellTestSupport.ShellQuote(corePath)}
            source {ShellTestSupport.ShellQuote(platformPath)}
            source {ShellTestSupport.ShellQuote(configPath)}

            _containai_write_workspace_state "/tmp/test-workspace" "data_volume" "test-vol"
            _containai_write_workspace_state "/tmp/test-workspace" "container_name" "my-container"

            ws_json=$(_containai_read_workspace_state "/tmp/test-workspace")
            ws_container=$(_containai_read_workspace_key "/tmp/test-workspace" "container_name")
            printf '%s\n%s' "$ws_json" "$ws_container"
            """,
            environment: new Dictionary<string, string?> { ["XDG_CONFIG_HOME"] = xdgPath },
            cancellationToken: cancellationToken);

        Assert.Equal(0, result.ExitCode);
        var lines = result.StdOut.Trim().Split('\n', StringSplitOptions.RemoveEmptyEntries);
        Assert.True(lines.Length >= 2);

        using var json = JsonDocument.Parse(lines[0]);
        Assert.Equal("test-vol", json.RootElement.GetProperty("data_volume").GetString());
        Assert.Equal("my-container", json.RootElement.GetProperty("container_name").GetString());
        Assert.Equal("my-container", lines[1]);
    }

    [Fact]
    public async Task WriteWorkspaceState_AllowsEmptyValue()
    {
        using var temp = ShellTestSupport.CreateTemporaryDirectory("cai-ws-empty");
        var xdgPath = Path.Combine(temp.Path, "config");
        var cancellationToken = TestContext.Current.CancellationToken;
        var corePath = Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/core.sh");
        var platformPath = Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/platform.sh");
        var configPath = Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/config.sh");

        var result = await ShellTestSupport.RunBashAsync(
            $"""
            source {ShellTestSupport.ShellQuote(corePath)}
            source {ShellTestSupport.ShellQuote(platformPath)}
            source {ShellTestSupport.ShellQuote(configPath)}

            _containai_write_workspace_state "/tmp/test-workspace" "agent" ""
            grep -q 'agent = ""' "{xdgPath}/containai/config.toml"
            """,
            environment: new Dictionary<string, string?> { ["XDG_CONFIG_HOME"] = xdgPath },
            cancellationToken: cancellationToken);

        Assert.Equal(0, result.ExitCode);
    }
}
