namespace ContainAI.Cli.Abstractions;

public sealed record ProcessExecutionSpec(
    string FileName,
    IReadOnlyList<string> Arguments,
    IReadOnlyDictionary<string, string?>? EnvironmentOverrides = null);

public sealed record DockerExecutionSpec(
    IReadOnlyList<string> Arguments,
    string ContextName = "containai-docker",
    bool PreferContainAiDockerExecutable = true);
