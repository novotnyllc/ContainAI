namespace ContainAI.Cli.Host;

internal interface IDevcontainerServiceBootstrap
{
    Task<int> VerifySysboxAsync(CancellationToken cancellationToken);

    Task<int> StartSshdAsync(CancellationToken cancellationToken);

    Task<int> StartDockerdAsync(CancellationToken cancellationToken);
}

internal sealed class DevcontainerServiceBootstrap : IDevcontainerServiceBootstrap
{
    private readonly IDevcontainerProcessHelpers processHelpers;
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly Func<string, string?> environmentVariableReader;

    public DevcontainerServiceBootstrap(
        IDevcontainerProcessHelpers processHelpers,
        TextWriter standardOutput,
        TextWriter standardError,
        Func<string, string?> environmentVariableReader)
    {
        this.processHelpers = processHelpers ?? throw new ArgumentNullException(nameof(processHelpers));
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        this.environmentVariableReader = environmentVariableReader ?? throw new ArgumentNullException(nameof(environmentVariableReader));
    }

    public async Task<int> VerifySysboxAsync(CancellationToken cancellationToken)
    {
        var passed = 0;
        var sysboxfsFound = false;
        await stdout.WriteLineAsync("ContainAI Sysbox Verification").ConfigureAwait(false);
        await stdout.WriteLineAsync("--------------------------------").ConfigureAwait(false);

        if (await processHelpers.IsSysboxFsMountedAsync(cancellationToken).ConfigureAwait(false))
        {
            sysboxfsFound = true;
            passed++;
            await stdout.WriteLineAsync("  [OK] Sysboxfs: mounted (REQUIRED)").ConfigureAwait(false);
        }
        else
        {
            await stdout.WriteLineAsync("  [FAIL] Sysboxfs: not found (REQUIRED)").ConfigureAwait(false);
        }

        if (await processHelpers.HasUidMappingIsolationAsync(cancellationToken).ConfigureAwait(false))
        {
            passed++;
            await stdout.WriteLineAsync("  [OK] UID mapping: sysbox user namespace").ConfigureAwait(false);
        }
        else
        {
            await stdout.WriteLineAsync("  [FAIL] UID mapping: 0->0 (not sysbox)").ConfigureAwait(false);
        }

        if (await processHelpers.CommandSucceedsAsync("unshare", ["--user", "--map-root-user", "true"], cancellationToken).ConfigureAwait(false))
        {
            passed++;
            await stdout.WriteLineAsync("  [OK] Nested userns: allowed").ConfigureAwait(false);
        }
        else
        {
            await stdout.WriteLineAsync("  [FAIL] Nested userns: blocked").ConfigureAwait(false);
        }

        var tempDirectory = Path.Combine(Path.GetTempPath(), $"containai-sysbox-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDirectory);
        var mountSucceeded = await processHelpers.CommandSucceedsAsync("mount", ["-t", "tmpfs", "none", tempDirectory], cancellationToken).ConfigureAwait(false);
        if (mountSucceeded)
        {
            _ = await processHelpers.CommandSucceedsAsync("umount", [tempDirectory], cancellationToken).ConfigureAwait(false);
            passed++;
            await stdout.WriteLineAsync("  [OK] Capabilities: CAP_SYS_ADMIN works").ConfigureAwait(false);
        }
        else
        {
            await stdout.WriteLineAsync("  [FAIL] Capabilities: mount denied").ConfigureAwait(false);
        }

        try
        {
            Directory.Delete(tempDirectory, recursive: true);
        }
        catch (IOException ex)
        {
            _ = ex;
        }
        catch (UnauthorizedAccessException ex)
        {
            _ = ex;
        }

        await stdout.WriteLineAsync($"\nPassed: {passed} checks").ConfigureAwait(false);
        if (!sysboxfsFound || passed < 3)
        {
            await stderr.WriteLineAsync("FAIL: sysbox verification failed").ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync("[OK] Running in sysbox sandbox").ConfigureAwait(false);
        return 0;
    }

    public async Task<int> StartSshdAsync(CancellationToken cancellationToken)
    {
        if (!await processHelpers.CommandExistsAsync("sshd", cancellationToken).ConfigureAwait(false))
        {
            await stderr.WriteLineAsync("Warning: sshd not installed").ConfigureAwait(false);
            return 0;
        }

        var sshPort = environmentVariableReader("CONTAINAI_SSH_PORT") ?? "2322";
        if (await processHelpers.IsSshdRunningFromPidFileAsync(DevcontainerFeaturePaths.DefaultSshPidFile, cancellationToken).ConfigureAwait(false))
        {
            await stdout.WriteLineAsync($"[OK] sshd already running on port {sshPort} (validated via pidfile)").ConfigureAwait(false);
            return 0;
        }

        if (processHelpers.IsPortInUse(sshPort))
        {
            await stdout.WriteLineAsync($"[OK] sshd appears to be running on port {sshPort} (port in use)").ConfigureAwait(false);
            return 0;
        }

        if (File.Exists(DevcontainerFeaturePaths.DefaultSshPidFile))
        {
            await processHelpers.RunAsRootAsync("rm", ["-f", DevcontainerFeaturePaths.DefaultSshPidFile], cancellationToken).ConfigureAwait(false);
        }

        await processHelpers.RunAsRootAsync("mkdir", ["-p", "/var/run/sshd"], cancellationToken).ConfigureAwait(false);
        await processHelpers.RunAsRootAsync("chmod", ["755", "/var/run/sshd"], cancellationToken).ConfigureAwait(false);

        if (!File.Exists("/etc/ssh/ssh_host_rsa_key"))
        {
            await processHelpers.RunAsRootAsync("ssh-keygen", ["-A"], cancellationToken).ConfigureAwait(false);
        }

        await processHelpers.RunAsRootAsync("/usr/sbin/sshd", ["-p", sshPort, "-o", $"PidFile={DevcontainerFeaturePaths.DefaultSshPidFile}"], cancellationToken).ConfigureAwait(false);
        await stdout.WriteLineAsync($"[OK] sshd started on port {sshPort}").ConfigureAwait(false);
        return 0;
    }

    public async Task<int> StartDockerdAsync(CancellationToken cancellationToken)
    {
        if (!await processHelpers.CommandExistsAsync("dockerd", cancellationToken).ConfigureAwait(false))
        {
            return 0;
        }

        if (File.Exists(DevcontainerFeaturePaths.DefaultDockerPidFile))
        {
            var pidRaw = await File.ReadAllTextAsync(DevcontainerFeaturePaths.DefaultDockerPidFile, cancellationToken).ConfigureAwait(false);
            if (int.TryParse(pidRaw.Trim(), out var existingPid) && processHelpers.IsProcessAlive(existingPid))
            {
                await stdout.WriteLineAsync($"[OK] dockerd already running (pid {existingPid})").ConfigureAwait(false);
                return 0;
            }

            await processHelpers.RunAsRootAsync("rm", ["-f", DevcontainerFeaturePaths.DefaultDockerPidFile], cancellationToken).ConfigureAwait(false);
        }

        if (await processHelpers.CommandSucceedsAsync("docker", ["info"], cancellationToken).ConfigureAwait(false))
        {
            await stdout.WriteLineAsync("[OK] dockerd already running (socket active)").ConfigureAwait(false);
            return 0;
        }

        await stdout.WriteLineAsync("Starting dockerd...").ConfigureAwait(false);
        await processHelpers.RunAsRootAsync(
            "sh",
            ["-c", $"nohup dockerd --pidfile={DevcontainerFeaturePaths.DefaultDockerPidFile} > {DevcontainerFeaturePaths.DefaultDockerLogFile} 2>&1 &"],
            cancellationToken).ConfigureAwait(false);

        for (var attempt = 0; attempt < 30; attempt++)
        {
            if (await processHelpers.CommandSucceedsAsync("docker", ["info"], cancellationToken).ConfigureAwait(false))
            {
                await stdout.WriteLineAsync("[OK] dockerd started (DinD ready)").ConfigureAwait(false);
                return 0;
            }

            await Task.Delay(TimeSpan.FromSeconds(1), cancellationToken).ConfigureAwait(false);
        }

        await stderr.WriteLineAsync($"[FAIL] dockerd failed to start (see {DevcontainerFeaturePaths.DefaultDockerLogFile})").ConfigureAwait(false);
        return 1;
    }
}
