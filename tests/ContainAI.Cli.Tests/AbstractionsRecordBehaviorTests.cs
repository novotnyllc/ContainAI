using ContainAI.Cli.Abstractions;
using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class AbstractionsRecordBehaviorTests
{
    [Fact]
    public void ProcessExecutionSpec_RecordMembersBehaveAsExpected()
    {
        IReadOnlyList<string> arguments = ["status", "--short"];
        IReadOnlyDictionary<string, string?> environment = new Dictionary<string, string?>
        {
            ["CONTAINAI_VERBOSE"] = "1",
        };

        var first = new ProcessExecutionSpec("git", arguments, environment);
        var same = new ProcessExecutionSpec("git", arguments, environment);
        var different = new ProcessExecutionSpec("docker", arguments, environment);

        Assert.True(first == same);
        Assert.True(first != different);
        Assert.True(first.Equals((object)same));
        Assert.False(first.Equals((object)different));
        Assert.Equal(first.GetHashCode(), same.GetHashCode());

        var updated = first with { FileName = "bash" };

        Assert.Equal("bash", updated.FileName);
        Assert.Equal(arguments, updated.Arguments);

        var (fileName, deconstructedArguments, deconstructedEnvironment) = first;

        Assert.Equal("git", fileName);
        Assert.Same(arguments, deconstructedArguments);
        Assert.Same(environment, deconstructedEnvironment);

        var text = first.ToString();

        Assert.Contains("ProcessExecutionSpec", text, StringComparison.Ordinal);
        Assert.Contains("FileName = git", text, StringComparison.Ordinal);
    }

    [Fact]
    public void DockerExecutionSpec_RecordMembersBehaveAsExpected()
    {
        IReadOnlyList<string> arguments = ["ps"];

        var first = new DockerExecutionSpec(arguments, "containai-docker", true);
        var same = new DockerExecutionSpec(arguments, "containai-docker", true);
        var different = new DockerExecutionSpec(arguments, "other-context", true);

        Assert.True(first == same);
        Assert.True(first != different);
        Assert.True(first.Equals((object)same));
        Assert.False(first.Equals((object)different));
        Assert.Equal(first.GetHashCode(), same.GetHashCode());

        var updated = first with { PreferContainAiDockerExecutable = false };

        Assert.False(updated.PreferContainAiDockerExecutable);
        Assert.Equal("containai-docker", updated.ContextName);

        var (deconstructedArguments, contextName, preferContainAiDockerExecutable) = first;

        Assert.Same(arguments, deconstructedArguments);
        Assert.Equal("containai-docker", contextName);
        Assert.True(preferContainAiDockerExecutable);

        var text = first.ToString();

        Assert.Contains("DockerExecutionSpec", text, StringComparison.Ordinal);
        Assert.Contains("ContextName = containai-docker", text, StringComparison.Ordinal);
    }

    [Fact]
    public void RunCommandOptions_RecordMembersBehaveAsExpected()
    {
        IReadOnlyList<string> env = ["FOO=bar"];
        IReadOnlyList<string> commandArgs = ["echo", "ok"];

        var first = new RunCommandOptions(
            Workspace: "/tmp/workspace",
            Fresh: true,
            Detached: true,
            Quiet: false,
            Verbose: true,
            Credentials: "copy",
            AcknowledgeCredentialRisk: true,
            DataVolume: "containai-data",
            Config: "/tmp/config.toml",
            Container: "containai-demo",
            Force: true,
            Debug: false,
            DryRun: false,
            ImageTag: "latest",
            Template: "default",
            Channel: "stable",
            Memory: "8g",
            Cpus: "4",
            Env: env,
            CommandArgs: commandArgs);
        var same = new RunCommandOptions(
            Workspace: "/tmp/workspace",
            Fresh: true,
            Detached: true,
            Quiet: false,
            Verbose: true,
            Credentials: "copy",
            AcknowledgeCredentialRisk: true,
            DataVolume: "containai-data",
            Config: "/tmp/config.toml",
            Container: "containai-demo",
            Force: true,
            Debug: false,
            DryRun: false,
            ImageTag: "latest",
            Template: "default",
            Channel: "stable",
            Memory: "8g",
            Cpus: "4",
            Env: env,
            CommandArgs: commandArgs);
        var different = first with { Container = "other-container" };

        Assert.True(first == same);
        Assert.True(first != different);
        Assert.True(first.Equals((object)same));
        Assert.False(first.Equals((object)different));
        Assert.Equal(first.GetHashCode(), same.GetHashCode());

        var updated = first with { Workspace = "/tmp/other", Detached = false };

        Assert.Equal("/tmp/other", updated.Workspace);
        Assert.False(updated.Detached);

        var (
            workspace,
            fresh,
            detached,
            quiet,
            verbose,
            credentials,
            acknowledgeCredentialRisk,
            dataVolume,
            config,
            container,
            force,
            debug,
            dryRun,
            imageTag,
            template,
            channel,
            memory,
            cpus,
            deconstructedEnv,
            deconstructedCommandArgs) = first;

        Assert.Equal("/tmp/workspace", workspace);
        Assert.True(fresh);
        Assert.True(detached);
        Assert.False(quiet);
        Assert.True(verbose);
        Assert.Equal("copy", credentials);
        Assert.True(acknowledgeCredentialRisk);
        Assert.Equal("containai-data", dataVolume);
        Assert.Equal("/tmp/config.toml", config);
        Assert.Equal("containai-demo", container);
        Assert.True(force);
        Assert.False(debug);
        Assert.False(dryRun);
        Assert.Equal("latest", imageTag);
        Assert.Equal("default", template);
        Assert.Equal("stable", channel);
        Assert.Equal("8g", memory);
        Assert.Equal("4", cpus);
        Assert.Same(env, deconstructedEnv);
        Assert.Same(commandArgs, deconstructedCommandArgs);

        var text = first.ToString();

        Assert.Contains("RunCommandOptions", text, StringComparison.Ordinal);
        Assert.Contains("Workspace = /tmp/workspace", text, StringComparison.Ordinal);
    }

    [Fact]
    public void ShellCommandOptions_RecordMembersBehaveAsExpected()
    {
        IReadOnlyList<string> commandArgs = ["bash"];

        var first = new ShellCommandOptions(
            Workspace: "/tmp/workspace",
            Fresh: true,
            Reset: true,
            Quiet: true,
            Verbose: false,
            DataVolume: "containai-data",
            Config: "/tmp/config.toml",
            Container: "containai-demo",
            Force: false,
            Debug: true,
            DryRun: true,
            ImageTag: "nightly",
            Template: "default",
            Channel: "preview",
            Memory: "16g",
            Cpus: "8",
            CommandArgs: commandArgs);
        var same = new ShellCommandOptions(
            Workspace: "/tmp/workspace",
            Fresh: true,
            Reset: true,
            Quiet: true,
            Verbose: false,
            DataVolume: "containai-data",
            Config: "/tmp/config.toml",
            Container: "containai-demo",
            Force: false,
            Debug: true,
            DryRun: true,
            ImageTag: "nightly",
            Template: "default",
            Channel: "preview",
            Memory: "16g",
            Cpus: "8",
            CommandArgs: commandArgs);
        var different = first with { Reset = false };

        Assert.True(first == same);
        Assert.True(first != different);
        Assert.True(first.Equals((object)same));
        Assert.False(first.Equals((object)different));
        Assert.Equal(first.GetHashCode(), same.GetHashCode());

        var updated = first with { Workspace = "/tmp/alternate" };

        Assert.Equal("/tmp/alternate", updated.Workspace);

        var (
            workspace,
            fresh,
            reset,
            quiet,
            verbose,
            dataVolume,
            config,
            container,
            force,
            debug,
            dryRun,
            imageTag,
            template,
            channel,
            memory,
            cpus,
            deconstructedCommandArgs) = first;

        Assert.Equal("/tmp/workspace", workspace);
        Assert.True(fresh);
        Assert.True(reset);
        Assert.True(quiet);
        Assert.False(verbose);
        Assert.Equal("containai-data", dataVolume);
        Assert.Equal("/tmp/config.toml", config);
        Assert.Equal("containai-demo", container);
        Assert.False(force);
        Assert.True(debug);
        Assert.True(dryRun);
        Assert.Equal("nightly", imageTag);
        Assert.Equal("default", template);
        Assert.Equal("preview", channel);
        Assert.Equal("16g", memory);
        Assert.Equal("8", cpus);
        Assert.Same(commandArgs, deconstructedCommandArgs);

        var text = first.ToString();

        Assert.Contains("ShellCommandOptions", text, StringComparison.Ordinal);
        Assert.Contains("Reset = True", text, StringComparison.Ordinal);
    }

    [Fact]
    public void ExecCommandOptions_RecordMembersBehaveAsExpected()
    {
        IReadOnlyList<string> commandArgs = ["bash", "-lc", "pwd"];

        var first = new ExecCommandOptions(
            Workspace: "/tmp/workspace",
            Quiet: false,
            Verbose: true,
            Container: "containai-demo",
            Template: "default",
            Channel: "stable",
            DataVolume: "containai-data",
            Config: "/tmp/config.toml",
            Fresh: true,
            Force: true,
            Debug: false,
            CommandArgs: commandArgs);
        var same = new ExecCommandOptions(
            Workspace: "/tmp/workspace",
            Quiet: false,
            Verbose: true,
            Container: "containai-demo",
            Template: "default",
            Channel: "stable",
            DataVolume: "containai-data",
            Config: "/tmp/config.toml",
            Fresh: true,
            Force: true,
            Debug: false,
            CommandArgs: commandArgs);
        var different = first with { Verbose = false };

        Assert.True(first == same);
        Assert.True(first != different);
        Assert.True(first.Equals((object)same));
        Assert.False(first.Equals((object)different));
        Assert.Equal(first.GetHashCode(), same.GetHashCode());

        var updated = first with { Quiet = true };

        Assert.True(updated.Quiet);

        var (
            workspace,
            quiet,
            verbose,
            container,
            template,
            channel,
            dataVolume,
            config,
            fresh,
            force,
            debug,
            deconstructedCommandArgs) = first;

        Assert.Equal("/tmp/workspace", workspace);
        Assert.False(quiet);
        Assert.True(verbose);
        Assert.Equal("containai-demo", container);
        Assert.Equal("default", template);
        Assert.Equal("stable", channel);
        Assert.Equal("containai-data", dataVolume);
        Assert.Equal("/tmp/config.toml", config);
        Assert.True(fresh);
        Assert.True(force);
        Assert.False(debug);
        Assert.Same(commandArgs, deconstructedCommandArgs);

        var text = first.ToString();

        Assert.Contains("ExecCommandOptions", text, StringComparison.Ordinal);
        Assert.Contains("Channel = stable", text, StringComparison.Ordinal);
    }

    [Fact]
    public void DockerCommandOptions_RecordMembersBehaveAsExpected()
    {
        IReadOnlyList<string> dockerArgs = ["images"];

        var first = new DockerCommandOptions(dockerArgs);
        var same = new DockerCommandOptions(dockerArgs);
        var different = new DockerCommandOptions(["ps"]);

        Assert.True(first == same);
        Assert.True(first != different);
        Assert.True(first.Equals((object)same));
        Assert.False(first.Equals((object)different));
        Assert.Equal(first.GetHashCode(), same.GetHashCode());

        var updated = first with { DockerArgs = ["ps", "-a"] };

        Assert.Equal(["ps", "-a"], updated.DockerArgs);

        first.Deconstruct(out var deconstructedDockerArgs);

        Assert.Same(dockerArgs, deconstructedDockerArgs);

        var text = first.ToString();

        Assert.Contains("DockerCommandOptions", text, StringComparison.Ordinal);
        Assert.Contains("DockerArgs =", text, StringComparison.Ordinal);
    }

    [Fact]
    public void StatusCommandOptions_RecordMembersBehaveAsExpected()
    {
        var first = new StatusCommandOptions(
            Json: true,
            Workspace: "/tmp/workspace",
            Container: "containai-demo",
            Verbose: false);
        var same = new StatusCommandOptions(
            Json: true,
            Workspace: "/tmp/workspace",
            Container: "containai-demo",
            Verbose: false);
        var different = first with { Json = false };

        Assert.True(first == same);
        Assert.True(first != different);
        Assert.True(first.Equals((object)same));
        Assert.False(first.Equals((object)different));
        Assert.Equal(first.GetHashCode(), same.GetHashCode());

        var updated = first with { Verbose = true };

        Assert.True(updated.Verbose);

        var (json, workspace, container, verbose) = first;

        Assert.True(json);
        Assert.Equal("/tmp/workspace", workspace);
        Assert.Equal("containai-demo", container);
        Assert.False(verbose);

        var text = first.ToString();

        Assert.Contains("StatusCommandOptions", text, StringComparison.Ordinal);
        Assert.Contains("Json = True", text, StringComparison.Ordinal);
    }
}
