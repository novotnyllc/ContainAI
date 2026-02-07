using AgentClientProtocol.Proxy.PathTranslation;
using Xunit;

namespace AgentClientProtocol.Proxy.Tests;

public sealed class WorkspaceResolverTests
{
    [Fact]
    public async Task ResolveAsync_WhenContainAiConfigExists_ReturnsContainingDirectory()
    {
        using var temp = new TempDirectory();
        var root = Path.Combine(temp.Path, "root");
        var nested = Path.Combine(root, "sub", "project");
        Directory.CreateDirectory(Path.Combine(root, ".containai"));
        await File.WriteAllTextAsync(
            Path.Combine(root, ".containai", "config.toml"),
            "workspace = \"default\"",
            TestContext.Current.CancellationToken);
        Directory.CreateDirectory(nested);

        var resolved = await WorkspaceResolver.ResolveAsync(nested, TestContext.Current.CancellationToken);

        Assert.Equal(root, resolved);
    }

    [Fact]
    public async Task ResolveAsync_WhenNoMarkersExist_ReturnsInputPath()
    {
        using var temp = new TempDirectory();
        var nested = Path.Combine(temp.Path, "nested", "workspace");
        Directory.CreateDirectory(nested);

        var resolved = await WorkspaceResolver.ResolveAsync(nested, TestContext.Current.CancellationToken);

        Assert.Equal(nested, resolved);
    }

    [Fact]
    public async Task ResolveAsync_WhenGitInvocationThrows_FallsBackToInputPath()
    {
        using var temp = new TempDirectory();
        var missingPath = Path.Combine(temp.Path, "missing", "workspace");

        var resolved = await WorkspaceResolver.ResolveAsync(missingPath, TestContext.Current.CancellationToken);

        Assert.Equal(missingPath, resolved);
    }

    [Fact]
    public async Task ResolveAsync_WhenCancelled_ThrowsOperationCanceledException()
    {
        using var temp = new TempDirectory();
        var nested = Path.Combine(temp.Path, "nested", "workspace");
        Directory.CreateDirectory(nested);

        using var cts = new CancellationTokenSource();
        await cts.CancelAsync();

        await Assert.ThrowsAsync<OperationCanceledException>(() => WorkspaceResolver.ResolveAsync(nested, cts.Token));
    }

    private sealed class TempDirectory : IDisposable
    {
        public TempDirectory()
        {
            Path = System.IO.Path.Combine(
                System.IO.Path.GetTempPath(),
                $"agent-client-protocol-{Guid.NewGuid():N}");
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
