namespace ContainAI.Cli;

internal static class RootCommandArgumentHelpers
{
    internal static string[] BuildArgumentList(string[]? parsedArgs, IReadOnlyList<string> unmatchedTokens)
        => (parsedArgs, unmatchedTokens.Count) switch
        {
            ({ Length: > 0 }, > 0) => [.. parsedArgs, .. unmatchedTokens],
            ({ Length: > 0 }, 0) => parsedArgs,
            (null or { Length: 0 }, > 0) => [.. unmatchedTokens],
            _ => Array.Empty<string>(),
        };
}
