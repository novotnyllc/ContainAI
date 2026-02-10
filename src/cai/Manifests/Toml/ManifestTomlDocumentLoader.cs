using CsToml;
using CsToml.Error;

namespace ContainAI.Cli.Host;

internal static class ManifestTomlDocumentLoader
{
    public static ManifestTomlDocument? Parse(string manifestFile)
    {
        try
        {
            var bytes = File.ReadAllBytes(manifestFile);
            return CsTomlSerializer.Deserialize<ManifestTomlDocument?>(bytes);
        }
        catch (CsTomlException ex)
        {
            throw new InvalidOperationException($"invalid TOML in manifest '{manifestFile}': {ex.Message}", ex);
        }
    }
}
