using ContainAI.Cli.Host.RuntimeSupport.Parsing;

namespace ContainAI.Cli.Host;

internal interface ICaiGcAgeParser
{
    bool TryParseMinimumAge(string ageValue, out TimeSpan minimumAge);
}

internal sealed class CaiGcAgeParser : ICaiGcAgeParser
{
    public bool TryParseMinimumAge(string ageValue, out TimeSpan minimumAge)
        => CaiRuntimeParseAndTimeHelpers.TryParseAgeDuration(ageValue, out minimumAge);
}
