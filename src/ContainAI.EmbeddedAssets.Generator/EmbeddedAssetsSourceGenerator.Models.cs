using System.Collections.Immutable;

namespace ContainAI.EmbeddedAssets.Generator;

public sealed partial class EmbeddedAssetsSourceGenerator
{
    private readonly struct AssetEntry
    {
        public AssetEntry(string key, string value)
        {
            Key = key;
            Value = value;
        }

        public string Key { get; }

        public string Value { get; }
    }

    private readonly struct ParsedResxFile
    {
        public ParsedResxFile(string path, ImmutableArray<AssetEntry> entries)
        {
            Path = path;
            Entries = entries;
        }

        public string Path { get; }

        public ImmutableArray<AssetEntry> Entries { get; }

        public static ParsedResxFile Empty(string path) => new(path, []);
    }

    private readonly struct AdditionalFileContent
    {
        public AdditionalFileContent(string path, string content)
        {
            Path = path;
            Content = content;
        }

        public string Path { get; }

        public string Content { get; }
    }
}
