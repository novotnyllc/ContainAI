using System.Collections.Frozen;
using System.Reflection;
using ContainAI.Cli;
using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class RootCommandBuilderInternalTests
{
    private static readonly string[] PsArgs = ["ps"];
    private static readonly FrozenSet<string> EmptyCommandSet = Array.Empty<string>().ToFrozenSet(StringComparer.Ordinal);
    private static readonly FrozenSet<string> RefreshCommandSet = new HashSet<string>(StringComparer.Ordinal) { "refresh" }.ToFrozenSet(StringComparer.Ordinal);
    private static readonly Type RootCommandBuilderType =
        typeof(CaiCli).Assembly.GetType("ContainAI.Cli.RootCommandBuilder")
        ?? throw new InvalidOperationException("RootCommandBuilder type not found.");

    [Fact]
    public void BuildArgumentList_WhenParsedAndUnmatchedPresent_AppendsInOrder()
    {
        var result = (IReadOnlyList<string>)InvokeStatic(
            "BuildArgumentList",
            [PsArgs, new List<string> { "--all" }]);

        Assert.Equal(["ps", "--all"], result);
    }

    [Fact]
    public void BuildArgumentList_WhenOnlyUnmatchedPresent_ReturnsUnmatched()
    {
        var result = (IReadOnlyList<string>)InvokeStatic(
            "BuildArgumentList",
            [Array.Empty<string>(), new List<string> { "--bogus" }]);

        Assert.Equal(["--bogus"], result);
    }

    [Fact]
    public void NormalizeCompletionInput_WithWhitespaceOnlyLine_ReturnsOriginalLineAndClampedCursor()
    {
        var result = ((string Line, int Cursor))InvokeStatic(
            "NormalizeCompletionInput",
            ["   ", 10]);

        Assert.Equal("   ", result.Line);
        Assert.Equal(3, result.Cursor);
    }

    [Fact]
    public void NormalizeCompletionInput_WithNonCaiInvocation_PreservesInput()
    {
        var result = ((string Line, int Cursor))InvokeStatic(
            "NormalizeCompletionInput",
            ["docker ps", 99]);

        Assert.Equal("docker ps", result.Line);
        Assert.Equal("docker ps".Length, result.Cursor);
    }

    [Fact]
    public void NormalizeCompletionInput_WithContainAiDockerInvocation_RewritesToDockerSubcommand()
    {
        var result = ((string Line, int Cursor))InvokeStatic(
            "NormalizeCompletionInput",
            ["containai-docker ru", 19]);

        Assert.Equal("docker ru", result.Line);
        Assert.Equal("docker ru".Length, result.Cursor);
    }

    [Fact]
    public void ExpandHome_WithoutTilde_ReturnsInputUnchanged()
    {
        var result = (string)InvokeStatic("ExpandHome", ["/tmp/workspace"]);

        Assert.Equal("/tmp/workspace", result);
    }

    [Fact]
    public void ExpandHome_WithTildeOnly_UsesHomeEnvironmentVariable()
    {
        var originalHome = Environment.GetEnvironmentVariable("HOME");
        try
        {
            Environment.SetEnvironmentVariable("HOME", "/tmp/cai-home");

            var result = (string)InvokeStatic("ExpandHome", ["~"]);

            Assert.Equal("/tmp/cai-home", result);
        }
        finally
        {
            Environment.SetEnvironmentVariable("HOME", originalHome);
        }
    }

    [Fact]
    public void ExpandHome_WithRelativeSegment_FallsBackToUserProfileWhenHomeMissing()
    {
        var originalHome = Environment.GetEnvironmentVariable("HOME");
        try
        {
            Environment.SetEnvironmentVariable("HOME", null);
            var expectedRoot = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

            var result = (string)InvokeStatic("ExpandHome", ["~/nested/path"]);

            Assert.StartsWith(expectedRoot, result, StringComparison.Ordinal);
            Assert.EndsWith(Path.Combine("nested", "path"), result, StringComparison.Ordinal);
        }
        finally
        {
            Environment.SetEnvironmentVariable("HOME", originalHome);
        }
    }

    [Fact]
    public void NormalizeCompletionArguments_WithRefreshAlias_RewritesToRefreshSubcommand()
    {
        var result = (IReadOnlyList<string>)InvokeStatic(
            "NormalizeCompletionArguments",
            ["--refresh --rebuild", RefreshCommandSet]);

        Assert.Equal(["refresh", "--rebuild"], result);
    }

    [Fact]
    public void NormalizeCompletionArguments_WithFlagFirstInput_PrependsRun()
    {
        var result = (IReadOnlyList<string>)InvokeStatic(
            "NormalizeCompletionArguments",
            ["--fresh /tmp/workspace", EmptyCommandSet]);

        Assert.Equal(["run", "--fresh", "/tmp/workspace"], result);
    }

    private static object InvokeStatic(string methodName, object?[] parameters)
    {
        var method = RootCommandBuilderType.GetMethod(methodName, BindingFlags.NonPublic | BindingFlags.Static)
            ?? throw new InvalidOperationException($"Method '{methodName}' not found.");

        try
        {
            return method.Invoke(null, parameters)
                ?? throw new InvalidOperationException($"Method '{methodName}' returned null.");
        }
        catch (TargetInvocationException ex) when (ex.InnerException is not null)
        {
            throw ex.InnerException;
        }
    }
}
