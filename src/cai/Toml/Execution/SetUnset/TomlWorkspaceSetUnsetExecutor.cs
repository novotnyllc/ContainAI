namespace ContainAI.Cli.Host;

internal sealed class TomlWorkspaceSetUnsetExecutor(
    TomlCommandExecutionServices services,
    TomlSetUnsetInputValidator inputValidator,
    TomlSetUnsetContentCoordinator contentCoordinator)
{
    public TomlCommandResult SetWorkspaceKey(string filePath, string workspacePath, string key, string value)
    {
        var validationError = inputValidator.ValidateWorkspaceKey(key)
            ?? TomlSetUnsetInputValidator.ValidateWorkspacePathAbsolute(workspacePath)
            ?? TomlSetUnsetInputValidator.ValidateWorkspacePathForSet(workspacePath);
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
        var validationError = inputValidator.ValidateWorkspaceKey(key)
            ?? TomlSetUnsetInputValidator.ValidateWorkspacePathAbsolute(workspacePath);
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
}
