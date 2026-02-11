namespace ContainAI.Cli.Host;

internal sealed partial class InstallAssetMaterializer
{
    private static bool WriteDefaultConfig(string homeDirectory)
    {
        if (!BuiltInAssets.TryGet("example:default-config.toml", out var content))
        {
            return false;
        }

        var configDir = Path.Combine(homeDirectory, ".config", "containai");
        var configPath = Path.Combine(configDir, "config.toml");
        if (File.Exists(configPath))
        {
            return false;
        }

        Directory.CreateDirectory(configDir);
        File.WriteAllText(configPath, EnsureTrailingNewLine(content));
        return true;
    }

    private static string EnsureTrailingNewLine(string content)
        => content.EndsWith('\n') ? content : content + Environment.NewLine;
}
