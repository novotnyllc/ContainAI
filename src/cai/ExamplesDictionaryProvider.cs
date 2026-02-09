namespace ContainAI.Cli.Host;

internal interface IExamplesDictionaryProvider
{
    IReadOnlyDictionary<string, string> GetExamples();
}
