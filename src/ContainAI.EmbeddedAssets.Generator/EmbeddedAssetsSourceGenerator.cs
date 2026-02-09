using System;
using Microsoft.CodeAnalysis;

namespace ContainAI.EmbeddedAssets.Generator;

[Generator]
public sealed partial class EmbeddedAssetsSourceGenerator : IIncrementalGenerator
{
    public void Initialize(IncrementalGeneratorInitializationContext context)
    {
        var additionalFileContents = context.AdditionalTextsProvider
            .Select(static (file, cancellationToken) => new AdditionalFileContent(
                file.Path ?? string.Empty,
                file.GetText(cancellationToken)?.ToString() ?? string.Empty))
            .Collect();

        var parsedResxFiles = context.AdditionalTextsProvider
            .Where(static file => IsResxFile(file.Path))
            .Combine(additionalFileContents)
            .Select(static (tuple, cancellationToken) => ParseResxFile(tuple.Left, tuple.Right, cancellationToken))
            .Where(static parsed => !parsed.Entries.IsDefaultOrEmpty)
            .Collect();

        context.RegisterSourceOutput(parsedResxFiles, static (productionContext, files) =>
            EmitBuiltInAssetsSource(productionContext, files));
    }

    private static bool IsResxFile(string? path)
        => path?.EndsWith(".resx", StringComparison.OrdinalIgnoreCase) == true;
}
