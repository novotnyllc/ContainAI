namespace ContainAI.Cli.Host;

internal interface IExamplesOutputPathResolver
{
    string NormalizePath(string value);
}
