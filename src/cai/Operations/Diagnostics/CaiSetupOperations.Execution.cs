namespace ContainAI.Cli.Host;

internal sealed partial class CaiSetupOperations
{
    private async Task<int> RunSetupCoreAsync(
        SetupPaths setupPaths,
        bool verbose,
        bool skipTemplates,
        CancellationToken cancellationToken)
    {
        if (!await EnsureDockerCliAvailableForSetupAsync(cancellationToken).ConfigureAwait(false))
        {
            return 1;
        }

        EnsureSetupDirectories(setupPaths.ContainAiDir, setupPaths.SshDir);
        if (await EnsureSetupSshKeyAsync(setupPaths.SshKeyPath, cancellationToken).ConfigureAwait(false) != 0)
        {
            return 1;
        }

        await EnsureRuntimeSocketForSetupAsync(setupPaths.SocketPath, cancellationToken).ConfigureAwait(false);
        await EnsureSetupDockerContextAsync(setupPaths.SocketPath, verbose, cancellationToken).ConfigureAwait(false);

        if (!skipTemplates)
        {
            var templateResult = await templateRestoreOperations
                .RestoreTemplatesAsync(templateName: null, includeAll: true, cancellationToken)
                .ConfigureAwait(false);
            if (templateResult != 0 && verbose)
            {
                await stderr.WriteLineAsync("Template installation completed with warnings.").ConfigureAwait(false);
            }
        }

        var doctorExitCode = await runDoctorPostSetupAsync(cancellationToken).ConfigureAwait(false);
        if (doctorExitCode != 0)
        {
            await stderr.WriteLineAsync("Setup completed with warnings. Run `cai doctor` for details.").ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync("Setup complete.").ConfigureAwait(false);
        return doctorExitCode;
    }
}
