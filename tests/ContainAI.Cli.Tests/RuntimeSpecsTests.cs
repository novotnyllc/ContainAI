using ContainAI.Cli.Abstractions;
using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class RuntimeSpecsTests
{
    [Fact]
    public void ProcessExecutionSpec_PreservesInputs()
    {
        var environment = new Dictionary<string, string?>
        {
            ["CONTAINAI_VERBOSE"] = "1",
            ["EMPTY"] = null,
        };

        var spec = new ProcessExecutionSpec(
            FileName: "git",
            Arguments: ["status", "--short"],
            EnvironmentOverrides: environment);

        Assert.Equal("git", spec.FileName);
        Assert.Equal(["status", "--short"], spec.Arguments);
        Assert.Equal("1", spec.EnvironmentOverrides?["CONTAINAI_VERBOSE"]);
        Assert.Null(spec.EnvironmentOverrides?["EMPTY"]);
    }

    [Fact]
    public void DockerExecutionSpec_DefaultsAreStable()
    {
        var spec = new DockerExecutionSpec(Arguments: ["ps"]);

        Assert.Equal(["ps"], spec.Arguments);
        Assert.Equal("containai-docker", spec.ContextName);
        Assert.True(spec.PreferContainAiDockerExecutable);
    }

    [Fact]
    public void RuntimeCommandOptions_RecordsCaptureValues()
    {
        var run = new RunCommandOptions("/tmp/workspace", Fresh: true, Detached: true, Quiet: true, Verbose: false, AdditionalArgs: ["--debug"], CommandArgs: ["echo", "ok"]);
        var shell = new ShellCommandOptions("/tmp/workspace", Quiet: false, Verbose: true, AdditionalArgs: ["--force"], CommandArgs: []);
        var exec = new ExecCommandOptions("/tmp/workspace", Quiet: true, Verbose: true, AdditionalArgs: ["--fresh"], CommandArgs: ["bash", "-lc", "pwd"]);
        var docker = new DockerCommandOptions(["images"]);
        var status = new StatusCommandOptions(Json: true, Workspace: "/tmp/workspace", Container: "containai-demo", Verbose: true, AdditionalArgs: []);

        Assert.Equal("/tmp/workspace", run.Workspace);
        Assert.Equal(["echo", "ok"], run.CommandArgs);
        Assert.Equal(["--debug"], run.AdditionalArgs);
        Assert.True(run.Fresh);
        Assert.True(run.Detached);
        Assert.True(run.Quiet);
        Assert.False(run.Verbose);

        Assert.Equal("/tmp/workspace", shell.Workspace);
        Assert.False(shell.Quiet);
        Assert.True(shell.Verbose);
        Assert.Equal(["--force"], shell.AdditionalArgs);
        Assert.Empty(shell.CommandArgs);

        Assert.Equal("/tmp/workspace", exec.Workspace);
        Assert.True(exec.Quiet);
        Assert.True(exec.Verbose);
        Assert.Equal(["--fresh"], exec.AdditionalArgs);
        Assert.Equal(["bash", "-lc", "pwd"], exec.CommandArgs);

        Assert.Equal(["images"], docker.DockerArgs);

        Assert.True(status.Json);
        Assert.Equal("/tmp/workspace", status.Workspace);
        Assert.Equal("containai-demo", status.Container);
        Assert.True(status.Verbose);
        Assert.Empty(status.AdditionalArgs);
    }

    [Fact]
    public void RuntimeCommandOptions_RecordEquality_IsValueBased()
    {
        var first = new StatusCommandOptions(
            Json: true,
            Workspace: "/tmp/workspace",
            Container: "containai-demo",
            Verbose: false,
            AdditionalArgs: ["--dry-run"]);
        var second = first with { };

        Assert.Equal(first, second);
        Assert.Equal(first.GetHashCode(), second.GetHashCode());
    }
}
