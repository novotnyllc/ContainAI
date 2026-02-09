using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Xml.Linq;
using Microsoft.CodeAnalysis;

namespace ContainAI.EmbeddedAssets.Generator;

public sealed partial class EmbeddedAssetsSourceGenerator
{
    private static ParsedResxFile ParseResxFile(
        AdditionalText file,
        ImmutableArray<AdditionalFileContent> additionalFiles,
        CancellationToken cancellationToken)
    {
        var filePath = file.Path ?? string.Empty;
        var content = file.GetText(cancellationToken)?.ToString();
        if (string.IsNullOrWhiteSpace(content))
        {
            return ParsedResxFile.Empty(filePath);
        }

        var additionalFileMap = BuildAdditionalFileMap(additionalFiles);

        try
        {
            var document = XDocument.Parse(content);
            var root = document.Root;
            if (root is null)
            {
                return ParsedResxFile.Empty(filePath);
            }

            var entries = ParseEntries(filePath, root, additionalFileMap);
            return new ParsedResxFile(filePath, entries);
        }
        catch (Exception ex) when (ShouldIgnoreResxParsingException(ex))
        {
            return ParsedResxFile.Empty(filePath);
        }
    }

    private static ImmutableArray<AssetEntry> ParseEntries(
        string filePath,
        XElement root,
        Dictionary<string, string> additionalFileMap)
    {
        var entries = ImmutableArray.CreateBuilder<AssetEntry>();
        foreach (var dataElement in root.Elements("data"))
        {
            var keyValue = dataElement.Attribute("name")?.Value;
            if (string.IsNullOrEmpty(keyValue))
            {
                continue;
            }

            var value = ResolveValue(filePath, dataElement, additionalFileMap);
            entries.Add(new AssetEntry(keyValue!, value));
        }

        return entries.ToImmutable();
    }
}
