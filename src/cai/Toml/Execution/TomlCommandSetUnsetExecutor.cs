using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host;

internal sealed class TomlCommandSetUnsetExecutor(
    TomlCommandExecutionServices services,
    Regex workspaceKeyRegex,
    Regex globalKeyRegex)
{
    private readonly TomlSetUnsetInputValidator inputValidator = new(services, workspaceKeyRegex, globalKeyRegex);
    private readonly TomlSetUnsetContentCoordinator contentCoordinator = new(services);

    public TomlCommandResult SetWorkspaceKey(string filePath, string workspacePath, string key, string value)
    {
        var validationError = inputValidator.ValidateWorkspaceKey(key);
        if (validationError is not null)
        {
            return validationError;
        }

        validationError = TomlSetUnsetInputValidator.ValidateWorkspacePathAbsolute(workspacePath);
        if (validationError is not null)
        {
            return validationError;
        }

        validationError = TomlSetUnsetInputValidator.ValidateWorkspacePathForSet(workspacePath);
        if (validationError is not null)
        {
            return validationError;
        }

        return contentCoordinator.UpdateContent(
            filePath,
            content => services.UpsertWorkspaceKey(content, workspacePath, key, value));
    }

    public TomlCommandResult UnsetWorkspaceKey(string filePath, string workspacePath, string key)
    {
        var validationError = inputValidator.ValidateWorkspaceKey(key);
        if (validationError is not null)
        {
            return validationError;
        }

        validationError = TomlSetUnsetInputValidator.ValidateWorkspacePathAbsolute(workspacePath);
        if (validationError is not null)
        {
            return validationError;
        }

        var missingFileResult = contentCoordinator.GetUnsetNoOpWhenFileMissing(filePath);
        if (missingFileResult is not null)
        {
            return missingFileResult;
        }

        return contentCoordinator.UpdateContent(
            filePath,
            content => services.RemoveWorkspaceKey(content, workspacePath, key));
    }

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
