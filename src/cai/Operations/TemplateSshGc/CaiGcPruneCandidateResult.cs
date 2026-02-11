namespace ContainAI.Cli.Host;

internal readonly record struct CaiGcPruneCandidateResult(
    int ExitCode,
    List<string> PruneCandidates,
    int Failures);
