namespace ContainAI.Cli.Host;

internal sealed partial class CaiGcOperations
{
    private readonly record struct CaiGcPruneCandidateResult(int ExitCode, List<string> PruneCandidates, int Failures);
}
