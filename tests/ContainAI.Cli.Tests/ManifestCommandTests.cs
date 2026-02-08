using ContainAI.Cli.Host;
using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class ManifestCommandTests
{
    [Fact]
    public async Task ManifestParse_SingleFile_EmitsEntries()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"cai-manifest-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            var manifestPath = Path.Combine(tempDir, "test.toml");
            await File.WriteAllTextAsync(
                manifestPath,
                """
                [agent]
                name = "test"
                binary = "test"
                default_args = ["--flag"]

                [[entries]]
                source = ".a"
                target = "a"
                container_link = ".a"
                flags = "f"

                [[entries]]
                source = ".b"
                target = "b"
                container_link = ".b"
                flags = "fo"
                """,
                TestContext.Current.CancellationToken);

            using var stdout = new StringWriter();
            using var stderr = new StringWriter();
            var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);
            var exitCode = await runtime.RunAsync(["manifest", "parse", manifestPath], TestContext.Current.CancellationToken);

            Assert.Equal(0, exitCode);
            var lines = stdout.ToString().Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            Assert.Equal(2, lines.Length);
            Assert.Contains(".a|a|.a|f|false|entry|false", lines, StringComparer.Ordinal);
            Assert.Contains(".b|b|.b|fo|false|entry|true", lines, StringComparer.Ordinal);
            Assert.Equal(string.Empty, stderr.ToString());
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public async Task ManifestParse_Directory_SortsByFileName()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"cai-manifest-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            await File.WriteAllTextAsync(
                Path.Combine(tempDir, "02-second.toml"),
                """
                [[entries]]
                source = ".second"
                target = "second"
                container_link = ".second"
                flags = "f"
                """,
                TestContext.Current.CancellationToken);

            await File.WriteAllTextAsync(
                Path.Combine(tempDir, "01-first.toml"),
                """
                [[entries]]
                source = ".first"
                target = "first"
                container_link = ".first"
                flags = "f"
                """,
                TestContext.Current.CancellationToken);

            using var stdout = new StringWriter();
            using var stderr = new StringWriter();
            var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);
            var exitCode = await runtime.RunAsync(["manifest", "parse", tempDir], TestContext.Current.CancellationToken);

            Assert.Equal(0, exitCode);
            var firstLine = stdout.ToString().Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)[0];
            Assert.Contains(".first|first|.first|f|false|entry|false", firstLine, StringComparison.Ordinal);
            Assert.Equal(string.Empty, stderr.ToString());
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public async Task ManifestParse_IncludeDisabled_EmitsDisabledEntries()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"cai-manifest-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            var manifestPath = Path.Combine(tempDir, "test.toml");
            await File.WriteAllTextAsync(
                manifestPath,
                """
                [[entries]]
                source = ".disabled"
                target = "disabled"
                container_link = ".disabled"
                flags = "f"
                disabled = true
                """,
                TestContext.Current.CancellationToken);

            using var stdout = new StringWriter();
            using var stderr = new StringWriter();
            var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);
            var exitCode = await runtime.RunAsync(
                ["manifest", "parse", "--include-disabled", manifestPath],
                TestContext.Current.CancellationToken);

            Assert.Equal(0, exitCode);
            Assert.Contains(".disabled|disabled|.disabled|f|true|entry|false", stdout.ToString(), StringComparison.Ordinal);
            Assert.Equal(string.Empty, stderr.ToString());
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public async Task ManifestParse_EmitSourceFile_AppendsSourcePath()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"cai-manifest-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            var manifestPath = Path.Combine(tempDir, "test.toml");
            await File.WriteAllTextAsync(
                manifestPath,
                """
                [[entries]]
                source = ".config"
                target = "config"
                container_link = ".config"
                flags = "f"
                """,
                TestContext.Current.CancellationToken);

            using var stdout = new StringWriter();
            using var stderr = new StringWriter();
            var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);
            var exitCode = await runtime.RunAsync(
                ["manifest", "parse", "--emit-source-file", manifestPath],
                TestContext.Current.CancellationToken);

            Assert.Equal(0, exitCode);
            Assert.Contains($"|{manifestPath}", stdout.ToString(), StringComparison.Ordinal);
            Assert.Equal(string.Empty, stderr.ToString());
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public async Task ManifestGenerate_ContainerLinkSpec_PrintsJsonToStdout()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"cai-manifest-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            var manifestPath = Path.Combine(tempDir, "test.toml");
            await File.WriteAllTextAsync(
                manifestPath,
                """
                [[entries]]
                source = ".test/config.json"
                target = "test/config.json"
                container_link = ".test/config.json"
                flags = "fR"
                """,
                TestContext.Current.CancellationToken);

            using var stdout = new StringWriter();
            using var stderr = new StringWriter();
            var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);
            var exitCode = await runtime.RunAsync(
                ["manifest", "generate", "container-link-spec", manifestPath],
                TestContext.Current.CancellationToken);

            Assert.Equal(0, exitCode);
            Assert.Contains("\"links\": [", stdout.ToString(), StringComparison.Ordinal);
            Assert.Contains("\"link\": \"/home/agent/.test/config.json\"", stdout.ToString(), StringComparison.Ordinal);
            Assert.Contains("\"target\": \"/mnt/agent-data/test/config.json\"", stdout.ToString(), StringComparison.Ordinal);
            Assert.Contains("\"remove_first\": true", stdout.ToString(), StringComparison.Ordinal);
            Assert.Equal(string.Empty, stderr.ToString());
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public async Task ManifestApply_InitDirs_CreatesExpectedTargets()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"cai-manifest-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            var manifestPath = Path.Combine(tempDir, "test.toml");
            var dataDir = Path.Combine(tempDir, "data");
            await File.WriteAllTextAsync(
                manifestPath,
                """
                [[entries]]
                source = ".config"
                target = "config"
                container_link = ".config"
                flags = "d"

                [[entries]]
                source = ".config/secret.json"
                target = "config/secret.json"
                container_link = ".config/secret.json"
                flags = "fjs"
                """,
                TestContext.Current.CancellationToken);

            using var stdout = new StringWriter();
            using var stderr = new StringWriter();
            var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);
            var exitCode = await runtime.RunAsync(
                ["manifest", "apply", "init-dirs", manifestPath, "--data-dir", dataDir],
                TestContext.Current.CancellationToken);

            Assert.Equal(0, exitCode);
            Assert.True(Directory.Exists(Path.Combine(dataDir, "config")));
            var secretPath = Path.Combine(dataDir, "config", "secret.json");
            Assert.True(File.Exists(secretPath));
            Assert.Equal("{}", await File.ReadAllTextAsync(secretPath, TestContext.Current.CancellationToken));
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public async Task ManifestApply_ContainerLinks_CreatesSymbolicLinks()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        var tempDir = Path.Combine(Path.GetTempPath(), $"cai-manifest-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            var manifestPath = Path.Combine(tempDir, "test.toml");
            var dataDir = Path.Combine(tempDir, "data");
            var homeDir = Path.Combine(tempDir, "home");
            Directory.CreateDirectory(dataDir);
            Directory.CreateDirectory(homeDir);
            Directory.CreateDirectory(Path.Combine(homeDir, ".gitconfig"));

            await File.WriteAllTextAsync(
                manifestPath,
                """
                [[entries]]
                source = ".gitconfig"
                target = "git/gitconfig"
                container_link = ".gitconfig"
                flags = "fR"
                """,
                TestContext.Current.CancellationToken);

            using var stdout = new StringWriter();
            using var stderr = new StringWriter();
            var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);
            var exitCode = await runtime.RunAsync(
                ["manifest", "apply", "container-links", manifestPath, "--home-dir", homeDir, "--data-dir", dataDir],
                TestContext.Current.CancellationToken);

            Assert.Equal(0, exitCode);

            var linkPath = Path.Combine(homeDir, ".gitconfig");
            var linkInfo = new FileInfo(linkPath);
            Assert.NotNull(linkInfo.LinkTarget);
            Assert.Equal(Path.Combine(dataDir, "git", "gitconfig"), Path.GetFullPath(Path.Combine(Path.GetDirectoryName(linkPath)!, linkInfo.LinkTarget!)));
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public async Task ManifestApply_AgentShims_CreatesSymlinkToCai()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        var tempDir = Path.Combine(Path.GetTempPath(), $"cai-manifest-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            var manifestPath = Path.Combine(tempDir, "test.toml");
            var shimDir = Path.Combine(tempDir, "shims");
            var binaryDir = Path.Combine(tempDir, "bin");
            Directory.CreateDirectory(binaryDir);
            var caiPath = Path.Combine(binaryDir, "cai");
            var agentBinaryPath = Path.Combine(binaryDir, "myagent");

            await File.WriteAllTextAsync(
                caiPath,
                "#!/usr/bin/env bash\nexit 0\n",
                TestContext.Current.CancellationToken);
            await File.WriteAllTextAsync(
                agentBinaryPath,
                "#!/usr/bin/env bash\nexit 0\n",
                TestContext.Current.CancellationToken);

            File.SetUnixFileMode(
                caiPath,
                UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
            File.SetUnixFileMode(
                agentBinaryPath,
                UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);

            var existingPath = Environment.GetEnvironmentVariable("PATH");
            Environment.SetEnvironmentVariable("PATH", $"{binaryDir}:{existingPath}");
            try
            {
                await File.WriteAllTextAsync(
                    manifestPath,
                    """
                    [agent]
                    name = "myagent"
                    binary = "myagent"
                    default_args = ["--auto"]
                    aliases = ["myagent-cli"]
                    """,
                    TestContext.Current.CancellationToken);

                using var stdout = new StringWriter();
                using var stderr = new StringWriter();
                var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);
                var exitCode = await runtime.RunAsync(
                    ["manifest", "apply", "agent-shims", manifestPath, "--shim-dir", shimDir, "--cai-binary", caiPath],
                    TestContext.Current.CancellationToken);

                Assert.Equal(0, exitCode);
                var shimPath = Path.Combine(shimDir, "myagent");
                var aliasPath = Path.Combine(shimDir, "myagent-cli");
                Assert.True(File.Exists(shimPath));
                Assert.True(File.Exists(aliasPath));

                var shimInfo = new FileInfo(shimPath);
                var aliasInfo = new FileInfo(aliasPath);
                Assert.NotNull(shimInfo.LinkTarget);
                Assert.NotNull(aliasInfo.LinkTarget);
            }
            finally
            {
                Environment.SetEnvironmentVariable("PATH", existingPath);
            }
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }
}
