using ContainAI.Cli.Host.DockerProxy.Models;

namespace ContainAI.Cli.Host.DockerProxy.Parsing.Arguments;

internal static class DockerProxyDevcontainerLabelParsing
{
    public static DevcontainerLabels ExtractDevcontainerLabels(IReadOnlyList<string> args)
    {
        string? configFile = null;
        string? localFolder = null;

        for (var index = 0; index < args.Count; index++)
        {
            var token = args[index];
            if (string.Equals(token, "--label", StringComparison.Ordinal) && index + 1 < args.Count)
            {
                ParseLabel(args[index + 1], ref configFile, ref localFolder);
                index++;
                continue;
            }

            if (token.StartsWith("--label=", StringComparison.Ordinal))
            {
                ParseLabel(token[8..], ref configFile, ref localFolder);
            }
        }

        return new DevcontainerLabels(configFile, localFolder);
    }

    private static void ParseLabel(string labelToken, ref string? configFile, ref string? localFolder)
    {
        if (labelToken.StartsWith("devcontainer.config_file=", StringComparison.Ordinal))
        {
            configFile = labelToken[25..];
            return;
        }

        if (labelToken.StartsWith("devcontainer.local_folder=", StringComparison.Ordinal))
        {
            localFolder = labelToken[26..];
        }
    }
}
