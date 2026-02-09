using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class InstallCommandRuntime
{
    private const string ContainAiDataHomeRelative = ".local/share/containai";
    private const string ContainAiBinHomeRelative = ".local/bin";

    private readonly TextWriter stderr;
    private readonly TextWriter stdout;

    public InstallCommandRuntime(
        TextWriter? standardOutput = null,
        TextWriter? standardError = null)
    {
        stdout = standardOutput ?? Console.Out;
        stderr = standardError ?? Console.Error;
    }

    public async Task<int> RunAsync(InstallCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);

        var installDir = ResolveInstallDirectory(options.InstallDir);
        var binDir = ResolveBinDirectory(options.BinDir);
        var homeDirectory = ResolveHomeDirectory();

        await WriteInfoAsync("ContainAI installer starting", cancellationToken).ConfigureAwait(false);
        await WriteInfoAsync($"Install directory: {installDir}", cancellationToken).ConfigureAwait(false);
        await WriteInfoAsync($"Binary directory: {binDir}", cancellationToken).ConfigureAwait(false);

        if (!string.IsNullOrWhiteSpace(options.Channel))
        {
            await WriteInfoAsync($"Channel: {options.Channel}", cancellationToken).ConfigureAwait(false);
        }

        var sourceExecutablePath = ResolveCurrentExecutablePath();
        if (sourceExecutablePath is null)
        {
            await WriteErrorAsync("Unable to resolve the current cai executable path.", cancellationToken).ConfigureAwait(false);
            return 1;
        }

        try
        {
            cancellationToken.ThrowIfCancellationRequested();

            var deployment = InstallDeploymentService.Deploy(sourceExecutablePath, installDir, binDir);
            var assets = InstallAssetMaterializer.Materialize(installDir, homeDirectory);

            await WriteSuccessAsync($"Installed binary: {deployment.InstalledExecutablePath}", cancellationToken).ConfigureAwait(false);
            await WriteSuccessAsync($"Installed wrapper: {deployment.WrapperPath}", cancellationToken).ConfigureAwait(false);
            await WriteSuccessAsync($"Installed docker proxy: {deployment.DockerProxyPath}", cancellationToken).ConfigureAwait(false);
            await WriteInfoAsync(
                $"Materialized assets (manifests={assets.ManifestFilesWritten}, templates={assets.TemplateFilesWritten}, examples={assets.ExampleFilesWritten}, default_config={assets.WroteDefaultConfig})",
                cancellationToken).ConfigureAwait(false);

            await EnsurePathConfigurationAsync(binDir, options.Yes, cancellationToken).ConfigureAwait(false);

            if (options.NoSetup)
            {
                await WriteInfoAsync("Skipping setup (--no-setup).", cancellationToken).ConfigureAwait(false);
                return 0;
            }

            return await RunSetupAsync(deployment.InstalledExecutablePath, options, cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (IOException ex)
        {
            await WriteErrorAsync(ex.Message, cancellationToken).ConfigureAwait(false);
            return 1;
        }
        catch (UnauthorizedAccessException ex)
        {
            await WriteErrorAsync(ex.Message, cancellationToken).ConfigureAwait(false);
            return 1;
        }
        catch (ArgumentException ex)
        {
            await WriteErrorAsync(ex.Message, cancellationToken).ConfigureAwait(false);
            return 1;
        }
        catch (NotSupportedException ex)
        {
            await WriteErrorAsync(ex.Message, cancellationToken).ConfigureAwait(false);
            return 1;
        }
        catch (InvalidOperationException ex)
        {
            await WriteErrorAsync(ex.Message, cancellationToken).ConfigureAwait(false);
            return 1;
        }
    }

    private async Task<int> RunSetupAsync(
        string installedBinary,
        InstallCommandOptions options,
        CancellationToken cancellationToken)
    {
        var environment = options.Yes
            ? new Dictionary<string, string?>(StringComparer.Ordinal) { ["CAI_YES"] = "1" }
            : null;

        var dryRunArgs = options.Verbose
            ? new[] { "setup", "--dry-run", "--verbose" }
            : new[] { "setup", "--dry-run" };
        var dryRun = await CliWrapProcessRunner.RunCaptureAsync(
            installedBinary,
            dryRunArgs,
            cancellationToken,
            environment: environment).ConfigureAwait(false);
        if (dryRun.ExitCode != 0)
        {
            await WriteWarningAsync("Dry-run setup failed; continuing with setup.", cancellationToken).ConfigureAwait(false);
            if (options.Verbose && !string.IsNullOrWhiteSpace(dryRun.StandardError))
            {
                await stderr.WriteLineAsync(dryRun.StandardError.Trim()).ConfigureAwait(false);
            }
        }

        var setupArgs = options.Verbose
            ? new[] { "setup", "--verbose" }
            : new[] { "setup" };
        await WriteInfoAsync("Running post-install setup.", cancellationToken).ConfigureAwait(false);
        var setupExitCode = await CliWrapProcessRunner.RunInteractiveAsync(
            installedBinary,
            setupArgs,
            cancellationToken,
            environment: environment).ConfigureAwait(false);
        if (setupExitCode == 0)
        {
            await WriteSuccessAsync("Post-install setup completed.", cancellationToken).ConfigureAwait(false);
            return 0;
        }

        await WriteWarningAsync($"Setup exited with code {setupExitCode}. Run `cai setup` to retry.", cancellationToken).ConfigureAwait(false);
        return setupExitCode;
    }

    private async Task EnsurePathConfigurationAsync(string binDir, bool autoUpdateShellConfig, CancellationToken cancellationToken)
    {
        if (IsPathEntryPresent(binDir))
        {
            return;
        }

        if (!autoUpdateShellConfig)
        {
            await WriteWarningAsync(
                $"`{binDir}` is not on PATH. Add it to your shell profile or rerun installer with --yes.",
                cancellationToken).ConfigureAwait(false);
            return;
        }

        var rcFile = ResolveShellProfilePath();
        var line = BuildPathExportLine(binDir);

        Directory.CreateDirectory(Path.GetDirectoryName(rcFile)!);
        var currentContent = File.Exists(rcFile) ? await File.ReadAllTextAsync(rcFile, cancellationToken).ConfigureAwait(false) : string.Empty;
        if (currentContent.Contains(line, StringComparison.Ordinal))
        {
            return;
        }

        var appendedContent = string.IsNullOrWhiteSpace(currentContent)
            ? line + Environment.NewLine
            : currentContent.TrimEnd() + Environment.NewLine + line + Environment.NewLine;
        await File.WriteAllTextAsync(rcFile, appendedContent, cancellationToken).ConfigureAwait(false);
        await WriteInfoAsync($"Updated PATH in {rcFile}", cancellationToken).ConfigureAwait(false);
    }

    private static string ResolveShellProfilePath()
    {
        var shellPath = Environment.GetEnvironmentVariable("SHELL") ?? string.Empty;
        var shellName = Path.GetFileName(shellPath);
        var home = ResolveHomeDirectory();

        return shellName switch
        {
            "zsh" => Path.Combine(home, ".zshrc"),
            "fish" => Path.Combine(home, ".config", "fish", "config.fish"),
            _ => File.Exists(Path.Combine(home, ".bash_profile"))
                ? Path.Combine(home, ".bash_profile")
                : Path.Combine(home, ".bashrc"),
        };
    }

    private static string BuildPathExportLine(string binDir)
    {
        var home = ResolveHomeDirectory().Replace('\\', '/');
        var normalized = binDir.Replace('\\', '/');
        if (normalized.StartsWith(home + "/", StringComparison.Ordinal))
        {
            normalized = "$HOME/" + normalized[(home.Length + 1)..];
        }

        return $"export PATH=\"{normalized}:$PATH\"";
    }

    private static bool IsPathEntryPresent(string binDir)
    {
        var pathValue = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(pathValue))
        {
            return false;
        }

        var normalizedBin = Path.GetFullPath(binDir)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var segments = pathValue.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        foreach (var segment in segments)
        {
            var normalizedSegment = Path.GetFullPath(segment)
                .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (string.Equals(normalizedSegment, normalizedBin, StringComparison.Ordinal))
            {
                return true;
            }
        }

        return false;
    }

    private static string? ResolveCurrentExecutablePath()
    {
        var processPath = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(processPath))
        {
            return null;
        }

        return File.Exists(processPath) ? processPath : null;
    }

    private static string ResolveInstallDirectory(string? optionValue)
        => ResolveDirectory(
            optionValue,
            Environment.GetEnvironmentVariable("CAI_INSTALL_DIR"),
            ContainAiDataHomeRelative);

    private static string ResolveBinDirectory(string? optionValue)
        => ResolveDirectory(
            optionValue,
            Environment.GetEnvironmentVariable("CAI_BIN_DIR"),
            ContainAiBinHomeRelative);

    private static string ResolveDirectory(string? optionValue, string? envValue, string homeRelative)
    {
        if (!string.IsNullOrWhiteSpace(optionValue))
        {
            return NormalizePath(optionValue);
        }

        if (!string.IsNullOrWhiteSpace(envValue))
        {
            return NormalizePath(envValue);
        }

        return Path.GetFullPath(Path.Combine(ResolveHomeDirectory(), homeRelative));
    }

    private static string ResolveHomeDirectory()
    {
        var home = Environment.GetEnvironmentVariable("HOME");
        if (!string.IsNullOrWhiteSpace(home))
        {
            return home;
        }

        var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (!string.IsNullOrWhiteSpace(userProfile))
        {
            return userProfile;
        }

        return Directory.GetCurrentDirectory();
    }

    private static string NormalizePath(string value)
    {
        var expanded = value.StartsWith("~/", StringComparison.Ordinal) || string.Equals(value, "~", StringComparison.Ordinal)
            ? Path.Combine(ResolveHomeDirectory(), value.Length == 1 ? string.Empty : value[2..])
            : value;

        return Path.GetFullPath(expanded);
    }

    private Task WriteInfoAsync(string message, CancellationToken cancellationToken)
        => WriteLineAsync(stdout, "INFO", message, cancellationToken);

    private Task WriteSuccessAsync(string message, CancellationToken cancellationToken)
        => WriteLineAsync(stdout, "OK", message, cancellationToken);

    private Task WriteWarningAsync(string message, CancellationToken cancellationToken)
        => WriteLineAsync(stderr, "WARN", message, cancellationToken);

    private Task WriteErrorAsync(string message, CancellationToken cancellationToken)
        => WriteLineAsync(stderr, "ERROR", message, cancellationToken);

    private static async Task WriteLineAsync(TextWriter writer, string level, string message, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await writer.WriteLineAsync($"[{level}] {message}").ConfigureAwait(false);
    }
}
