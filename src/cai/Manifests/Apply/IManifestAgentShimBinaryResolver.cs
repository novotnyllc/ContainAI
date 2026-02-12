namespace ContainAI.Cli.Host.Manifests.Apply;

internal interface IManifestAgentShimBinaryResolver
{
    string? ResolveBinaryPath(string binary, string shimRoot, string caiPath);
}
