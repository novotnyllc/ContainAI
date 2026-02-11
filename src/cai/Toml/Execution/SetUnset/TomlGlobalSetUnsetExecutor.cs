namespace ContainAI.Cli.Host;

internal sealed class TomlGlobalSetUnsetExecutor(
    TomlCommandExecutionServices services,
    TomlSetUnsetInputValidator inputValidator,
    TomlSetUnsetContentCoordinator contentCoordinator)
{
    public TomlCommandResult SetKey(string filePath, string key, string value)
    {
        var validationError = inputValidator.ValidateGlobalKey(key);
        if (validationError is not null)
        {
            return validationError;
        }

        validationError = TomlSetUnsetInputValidator.ValidateGlobalSetKeyParts(key, out var parts);
        if (validationError is not null)
        {
            return validationError;
        }

        validationError = inputValidator.ValidateGlobalSetValue(key, value, out var formattedValue);
        if (validationError is not null)
        {
            return validationError;
        }

        return contentCoordinator.UpdateContent(
            filePath,
            content => services.UpsertGlobalKey(content, parts, formattedValue));
    }

    public TomlCommandResult UnsetKey(string filePath, string key)
    {
        var validationError = inputValidator.ValidateGlobalKey(key);
        if (validationError is not null)
        {
            return validationError;
        }

        var missingFileResult = contentCoordinator.GetUnsetNoOpWhenFileMissing(filePath);
        if (missingFileResult is not null)
        {
            return missingFileResult;
        }

        validationError = TomlSetUnsetInputValidator.ValidateGlobalUnsetKeyParts(key, out var parts);
        if (validationError is not null)
        {
            return validationError;
        }

        return contentCoordinator.UpdateContent(filePath, content => services.RemoveGlobalKey(content, parts));
    }
}
