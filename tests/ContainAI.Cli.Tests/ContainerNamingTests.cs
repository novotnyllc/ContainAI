using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class ContainerNamingTests
{
    [Fact]
    public async Task UsesRepositoryAndBranchLeaf()
    {
        using var temp = ShellTestSupport.CreateTemporaryDirectory("cai-container-name");
        var repoPath = Path.Combine(temp.Path, "MyRepo");
        var cancellationToken = TestContext.Current.CancellationToken;

        var result = await ShellTestSupport.RunBashAsync(
            $"""
            REPO_DIR={ShellTestSupport.ShellQuote(repoPath)}
            mkdir -p "$REPO_DIR"
            git -C "$REPO_DIR" init -q
            git -C "$REPO_DIR" config user.email "test@example.com"
            git -C "$REPO_DIR" config user.name "Test User"
            git -C "$REPO_DIR" config commit.gpgsign false
            printf '%s\n' "test" > "$REPO_DIR/file.txt"
            git -C "$REPO_DIR" add file.txt
            git -C "$REPO_DIR" commit -q -m "init"
            git -C "$REPO_DIR" checkout -q -b "feature/One"
            source {ShellTestSupport.ShellQuote(Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/container.sh"))}
            _containai_container_name "$REPO_DIR"
            """,
            cancellationToken: cancellationToken);

        Assert.Equal(0, result.ExitCode);
        Assert.Equal("myrepo-one", result.StdOut.Trim());
    }

    [Fact]
    public async Task UsesDetachedTokenForDetachedHead()
    {
        using var temp = ShellTestSupport.CreateTemporaryDirectory("cai-container-detached");
        var repoPath = Path.Combine(temp.Path, "MyRepo");
        var cancellationToken = TestContext.Current.CancellationToken;

        var result = await ShellTestSupport.RunBashAsync(
            $"""
            REPO_DIR={ShellTestSupport.ShellQuote(repoPath)}
            mkdir -p "$REPO_DIR"
            git -C "$REPO_DIR" init -q
            git -C "$REPO_DIR" config user.email "test@example.com"
            git -C "$REPO_DIR" config user.name "Test User"
            git -C "$REPO_DIR" config commit.gpgsign false
            printf '%s\n' "test" > "$REPO_DIR/file.txt"
            git -C "$REPO_DIR" add file.txt
            git -C "$REPO_DIR" commit -q -m "init"
            git -C "$REPO_DIR" checkout -q --detach
            source {ShellTestSupport.ShellQuote(Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/container.sh"))}
            _containai_container_name "$REPO_DIR"
            """,
            cancellationToken: cancellationToken);

        Assert.Equal(0, result.ExitCode);
        Assert.Equal("myrepo-detached", result.StdOut.Trim());
    }

    [Fact]
    public async Task UsesNoGitForNonGitDirectory()
    {
        using var temp = ShellTestSupport.CreateTemporaryDirectory("cai-container-nogit");
        var path = Path.Combine(temp.Path, "NoGit");
        Directory.CreateDirectory(path);
        var cancellationToken = TestContext.Current.CancellationToken;

        var result = await ShellTestSupport.RunBashAsync(
            $"""
            TARGET_DIR={ShellTestSupport.ShellQuote(path)}
            source {ShellTestSupport.ShellQuote(Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/container.sh"))}
            _containai_container_name "$TARGET_DIR"
            """,
            cancellationToken: cancellationToken);

        Assert.Equal(0, result.ExitCode);
        Assert.Equal("nogit-nogit", result.StdOut.Trim());
    }

    [Fact]
    public async Task TruncatesResultToTwentyFourCharacters()
    {
        using var temp = ShellTestSupport.CreateTemporaryDirectory("cai-container-truncate");
        var longRepo = new string('r', 40);
        var longBranch = new string('b', 40);
        var repoPath = Path.Combine(temp.Path, longRepo);
        var cancellationToken = TestContext.Current.CancellationToken;

        var result = await ShellTestSupport.RunBashAsync(
            $"""
            REPO_DIR={ShellTestSupport.ShellQuote(repoPath)}
            BRANCH_NAME={ShellTestSupport.ShellQuote(longBranch)}
            mkdir -p "$REPO_DIR"
            git -C "$REPO_DIR" init -q
            git -C "$REPO_DIR" config user.email "test@example.com"
            git -C "$REPO_DIR" config user.name "Test User"
            git -C "$REPO_DIR" config commit.gpgsign false
            printf '%s\n' "test" > "$REPO_DIR/file.txt"
            git -C "$REPO_DIR" add file.txt
            git -C "$REPO_DIR" commit -q -m "init"
            git -C "$REPO_DIR" checkout -q -b "$BRANCH_NAME"
            source {ShellTestSupport.ShellQuote(Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/container.sh"))}
            _containai_container_name "$REPO_DIR"
            """,
            cancellationToken: cancellationToken);

        Assert.Equal(0, result.ExitCode);
        var name = result.StdOut.Trim();
        Assert.True(name.Length <= 24, $"expected <= 24 chars but got '{name}' ({name.Length})");
        Assert.Contains('-', name);
        Assert.False(name.StartsWith("-", StringComparison.Ordinal));
        Assert.False(name.EndsWith("-", StringComparison.Ordinal));
    }

    [Fact]
    public async Task UsesSanitizationFallbackWhenSegmentsBecomeEmpty()
    {
        using var temp = ShellTestSupport.CreateTemporaryDirectory("cai-container-sanitize");
        var repoPath = Path.Combine(temp.Path, "___");
        var cancellationToken = TestContext.Current.CancellationToken;

        var result = await ShellTestSupport.RunBashAsync(
            $"""
            REPO_DIR={ShellTestSupport.ShellQuote(repoPath)}
            mkdir -p "$REPO_DIR"
            git -C "$REPO_DIR" init -q
            git -C "$REPO_DIR" config user.email "test@example.com"
            git -C "$REPO_DIR" config user.name "Test User"
            git -C "$REPO_DIR" config commit.gpgsign false
            printf '%s\n' "test" > "$REPO_DIR/file.txt"
            git -C "$REPO_DIR" add file.txt
            git -C "$REPO_DIR" commit -q -m "init"
            git -C "$REPO_DIR" checkout -q -b "___"
            source {ShellTestSupport.ShellQuote(Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/container.sh"))}
            _containai_container_name "$REPO_DIR"
            """,
            cancellationToken: cancellationToken);

        Assert.Equal(0, result.ExitCode);
        Assert.Equal("repo-branch", result.StdOut.Trim());
    }

    [Fact]
    public async Task UsesLeafForMultiSegmentBranchNames()
    {
        using var temp = ShellTestSupport.CreateTemporaryDirectory("cai-container-leaf");
        var repoPath = Path.Combine(temp.Path, "my-app");
        var cancellationToken = TestContext.Current.CancellationToken;

        var result = await ShellTestSupport.RunBashAsync(
            $"""
            REPO_DIR={ShellTestSupport.ShellQuote(repoPath)}
            mkdir -p "$REPO_DIR"
            git -C "$REPO_DIR" init -q
            git -C "$REPO_DIR" config user.email "test@example.com"
            git -C "$REPO_DIR" config user.name "Test User"
            git -C "$REPO_DIR" config commit.gpgsign false
            printf '%s\n' "test" > "$REPO_DIR/file.txt"
            git -C "$REPO_DIR" add file.txt
            git -C "$REPO_DIR" commit -q -m "init"
            git -C "$REPO_DIR" checkout -q -b "feat/ui/button"
            source {ShellTestSupport.ShellQuote(Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/container.sh"))}
            _containai_container_name "$REPO_DIR"
            """,
            cancellationToken: cancellationToken);

        Assert.Equal(0, result.ExitCode);
        Assert.Equal("my-app-button", result.StdOut.Trim());
    }

    [Fact]
    public async Task PreservesSimpleBranchNames()
    {
        using var temp = ShellTestSupport.CreateTemporaryDirectory("cai-container-simple");
        var repoPath = Path.Combine(temp.Path, "project");
        var cancellationToken = TestContext.Current.CancellationToken;

        var result = await ShellTestSupport.RunBashAsync(
            $"""
            REPO_DIR={ShellTestSupport.ShellQuote(repoPath)}
            mkdir -p "$REPO_DIR"
            git -C "$REPO_DIR" init -q
            git -C "$REPO_DIR" config user.email "test@example.com"
            git -C "$REPO_DIR" config user.name "Test User"
            git -C "$REPO_DIR" config commit.gpgsign false
            printf '%s\n' "test" > "$REPO_DIR/file.txt"
            git -C "$REPO_DIR" add file.txt
            git -C "$REPO_DIR" commit -q -m "init"
            git -C "$REPO_DIR" checkout -q -b "develop"
            source {ShellTestSupport.ShellQuote(Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/container.sh"))}
            _containai_container_name "$REPO_DIR"
            """,
            cancellationToken: cancellationToken);

        Assert.Equal(0, result.ExitCode);
        Assert.Equal("project-develop", result.StdOut.Trim());
    }
}
