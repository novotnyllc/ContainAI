namespace ContainAI.Cli.Host;

internal sealed class ExamplesStaticDictionaryProvider : IExamplesDictionaryProvider
{
    public IReadOnlyDictionary<string, string> GetExamples()
    {
        var dictionary = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var (name, content) in BuiltInAssets.EnumerateByPrefix("example:"))
        {
            dictionary[name] = content;
        }

        return dictionary;
    }
}
