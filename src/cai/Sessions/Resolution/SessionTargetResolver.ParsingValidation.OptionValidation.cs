namespace ContainAI.Cli.Host;

internal sealed partial class SessionTargetParsingValidationService
{
    public ResolvedTarget? ValidateOptions(SessionCommandOptions options)
    {
        if (!string.IsNullOrWhiteSpace(options.Container))
        {
            if (!string.IsNullOrWhiteSpace(options.Workspace))
            {
                return ResolvedTarget.ErrorResult("--container and --workspace are mutually exclusive");
            }

            if (!string.IsNullOrWhiteSpace(options.DataVolume))
            {
                return ResolvedTarget.ErrorResult("--container and --data-volume are mutually exclusive");
            }
        }

        if (options.Mode == SessionMode.Shell && options.Reset)
        {
            if (options.Fresh)
            {
                return ResolvedTarget.ErrorResult("--reset and --fresh are mutually exclusive");
            }

            if (!string.IsNullOrWhiteSpace(options.Container))
            {
                return ResolvedTarget.ErrorResult("--reset and --container are mutually exclusive");
            }

            if (!string.IsNullOrWhiteSpace(options.DataVolume))
            {
                return ResolvedTarget.ErrorResult("--reset and --data-volume are mutually exclusive");
            }
        }

        return null;
    }
}
