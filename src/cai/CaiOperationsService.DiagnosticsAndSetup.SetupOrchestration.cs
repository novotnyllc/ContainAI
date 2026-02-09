using System.ComponentModel;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiOperationsService : CaiRuntimeSupport
{
    private async Task<int> RunSetupCoreAsync(
        bool dryRun,
        bool verbose,
        bool skipTemplates,
        bool showHelp,
        CancellationToken cancellationToken)
    {
        if (showHelp)
        {
            await stdout.WriteLineAsync("Usage: cai setup [--dry-run] [--verbose] [--skip-templates]").ConfigureAwait(false);
            return 0;
        }

        var home = ResolveHomeDirectory();
        var containAiDir = Path.Combine(home, ".config", "containai");
        var sshDir = Path.Combine(home, ".ssh", "containai.d");
        var sshKeyPath = Path.Combine(containAiDir, "id_containai");
        var socketPath = "/var/run/containai-docker.sock";

        if (dryRun)
        {
            await stdout.WriteLineAsync($"Would create {containAiDir}").ConfigureAwait(false);
            await stdout.WriteLineAsync($"Would create {sshDir}").ConfigureAwait(false);
            await stdout.WriteLineAsync($"Would generate SSH key {sshKeyPath}").ConfigureAwait(false);
            await stdout.WriteLineAsync($"Would verify runtime socket {socketPath}").ConfigureAwait(false);
            await stdout.WriteLineAsync("Would create Docker context containai-docker").ConfigureAwait(false);
            if (!skipTemplates)
            {
                await stdout.WriteLineAsync($"Would install templates to {ResolveTemplatesDirectory()}").ConfigureAwait(false);
            }

            return 0;
        }

        if (!await EnsureDockerCliAvailableForSetupAsync(cancellationToken).ConfigureAwait(false))
        {
            return 1;
        }

        EnsureSetupDirectories(containAiDir, sshDir);
        if (await EnsureSetupSshKeyAsync(sshKeyPath, cancellationToken).ConfigureAwait(false) != 0)
        {
            return 1;
        }

        await EnsureRuntimeSocketForSetupAsync(socketPath, cancellationToken).ConfigureAwait(false);
        await EnsureSetupDockerContextAsync(socketPath, verbose, cancellationToken).ConfigureAwait(false);

        if (!skipTemplates)
        {
            var templateResult = await RestoreTemplatesAsync(templateName: null, includeAll: true, cancellationToken).ConfigureAwait(false);
            if (templateResult != 0 && verbose)
            {
                await stderr.WriteLineAsync("Template installation completed with warnings.").ConfigureAwait(false);
            }
        }

        var doctorExitCode = await RunDoctorCoreAsync(outputJson: false, buildTemplates: false, resetLima: false, cancellationToken).ConfigureAwait(false);
        if (doctorExitCode != 0)
        {
            await stderr.WriteLineAsync("Setup completed with warnings. Run `cai doctor` for details.").ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync("Setup complete.").ConfigureAwait(false);
        return doctorExitCode;
    }

    private async Task<int> RunDoctorFixCoreAsync(
        bool fixAll,
        bool dryRun,
        string? target,
        string? targetArg,
        CancellationToken cancellationToken)
    {
        if (target is null && !fixAll)
        {
            await stdout.WriteLineAsync("Available doctor fix targets:").ConfigureAwait(false);
            await stdout.WriteLineAsync("  --all").ConfigureAwait(false);
            await stdout.WriteLineAsync("  container [--all|<name>]").ConfigureAwait(false);
            await stdout.WriteLineAsync("  template [--all|<name>]").ConfigureAwait(false);
            return 0;
        }

        var containAiDir = Path.Combine(ResolveHomeDirectory(), ".config", "containai");
        var sshDir = Path.Combine(ResolveHomeDirectory(), ".ssh", "containai.d");
        if (dryRun)
        {
            await stdout.WriteLineAsync($"Would create {containAiDir} and {sshDir}").ConfigureAwait(false);
            await stdout.WriteLineAsync("Would ensure SSH include directive and cleanup stale SSH configs").ConfigureAwait(false);
        }
        else
        {
            Directory.CreateDirectory(containAiDir);
            Directory.CreateDirectory(sshDir);
            await EnsureSshIncludeDirectiveAsync(cancellationToken).ConfigureAwait(false);
            _ = await RunSshCleanupCoreAsync(dryRun: false, cancellationToken).ConfigureAwait(false);
        }

        if (fixAll || string.Equals(target, "template", StringComparison.Ordinal))
        {
            var templateResult = await RestoreTemplatesAsync(targetArg, includeAll: fixAll || string.Equals(targetArg, "--all", StringComparison.Ordinal), cancellationToken).ConfigureAwait(false);
            if (templateResult != 0)
            {
                return templateResult;
            }
        }

        if (fixAll || string.Equals(target, "container", StringComparison.Ordinal))
        {
            if (string.IsNullOrWhiteSpace(targetArg) || string.Equals(targetArg, "--all", StringComparison.Ordinal))
            {
                await stdout.WriteLineAsync("Container fix completed (SSH cleanup applied).").ConfigureAwait(false);
            }
            else
            {
                var exists = await DockerContainerExistsAsync(targetArg, cancellationToken).ConfigureAwait(false);
                if (!exists)
                {
                    await stderr.WriteLineAsync($"Container not found: {targetArg}").ConfigureAwait(false);
                    return 1;
                }

                await stdout.WriteLineAsync($"Container fix completed for {targetArg}.").ConfigureAwait(false);
            }
        }

        return 0;
    }
}
