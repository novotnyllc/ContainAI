namespace ContainAI.Cli.Host;

internal interface IShellProfileScriptContentGenerator
{
    string BuildProfileScript(string homeDirectory, string binDirectory);
}
