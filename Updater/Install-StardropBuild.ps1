function Assert-StardropClosed([string]$InstallDirectory) {
    $exe = Join-Path $InstallDirectory 'Stardrop.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Stardrop.exe was not found in $InstallDirectory" }
    if (Get-Process -Name Stardrop -ErrorAction SilentlyContinue) { throw 'Close Stardrop before updating it.' }
    [IO.File]::Open($exe, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None).Dispose()
}

function Get-StardropFileHash([string]$Path) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::OpenRead($Path)
        try { return [Convert]::ToBase64String($algorithm.ComputeHash($stream)) }
        finally { $stream.Dispose() }
    } finally {
        $algorithm.Dispose()
    }
}

function Install-StardropBuild([string]$BuildDirectory, [string]$InstallDirectory) {
    $install = (Resolve-Path -LiteralPath $InstallDirectory).Path
    Assert-StardropClosed $install
    $lock = [IO.FileStream]::new((Join-Path $install '.stardrop-update.lock'), [IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite, [IO.FileShare]::None, 4096, [IO.FileOptions]::DeleteOnClose)
    try {
        Copy-StardropBuildFiles $BuildDirectory $install
    } finally {
        $lock.Dispose()
    }
}

function Copy-StardropBuildFiles([string]$BuildDirectory, [string]$InstallDirectory) {
    $build = (Resolve-Path -LiteralPath $BuildDirectory).Path.TrimEnd('\','/')
    $install = (Resolve-Path -LiteralPath $InstallDirectory).Path.TrimEnd('\','/')
    if ($build -eq $install) { throw 'Build and installation directories must be different.' }
    Assert-StardropClosed $install

    $suffix = [Guid]::NewGuid().ToString('N')
    $backupDirectory = Join-Path $install ('Update Backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $suffix.Substring(0, 8))
    # Update resources first and swap the executable last. Existing themes and backups are kept.
    $published = @(
        foreach ($resource in 'i18n','Themes') {
            Get-ChildItem -LiteralPath (Join-Path $build $resource) -File -Recurse
        }
        $pdb = Join-Path $build 'Stardrop.pdb'
        if (Test-Path -LiteralPath $pdb -PathType Leaf) { Get-Item -LiteralPath $pdb }
        Get-Item -LiteralPath (Join-Path $build 'Stardrop.exe')
    )
    $files = @(
        foreach ($file in $published) {
            $relative = $file.FullName.Substring($build.Length + 1)
            $target = Join-Path $install $relative
            $hash = Get-StardropFileHash $file.FullName
            if ((Test-Path -LiteralPath $target -PathType Leaf) -and
                (Get-StardropFileHash $target) -ceq $hash) { continue }
            @{
                Source = $file.FullName
                Target = $target
                Backup = Join-Path $backupDirectory $relative
                Stage = $target + '.' + $suffix + '.tmp'
                HadOriginal = Test-Path -LiteralPath $target -PathType Leaf
                Hash = $hash
            }
        }
    )
    $installed = [Collections.Generic.List[hashtable]]::new()
    try {
        foreach ($file in $files) {
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($file.Target)) | Out-Null
            [IO.File]::Copy($file.Source, $file.Stage)
            if ((Get-StardropFileHash $file.Stage) -cne $file.Hash) {
                throw "Staging verification failed for $($file.Target)"
            }
        }
        Assert-StardropClosed $install
        foreach ($file in $files) {
            if ($file.HadOriginal) {
                [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($file.Backup)) | Out-Null
                [IO.File]::Replace($file.Stage, $file.Target, $file.Backup)
            } else {
                [IO.File]::Move($file.Stage, $file.Target)
            }
            $installed.Add($file)
            if ((Get-StardropFileHash $file.Target) -cne $file.Hash) {
                throw "Installation verification failed for $($file.Target)"
            }
        }
    } catch {
        for ($index = $installed.Count - 1; $index -ge 0; $index--) {
            $file = $installed[$index]
            try {
                if ($file.HadOriginal) {
                    [IO.File]::Replace($file.Backup, $file.Target, [NullString]::Value)
                } else {
                    [IO.File]::Delete($file.Target)
                }
            } catch {
                Write-Warning "Could not restore $($file.Target). Check $backupDirectory."
            }
        }
        throw
    } finally {
        foreach ($file in $files) {
            if (Test-Path -LiteralPath $file.Stage) { Remove-Item -LiteralPath $file.Stage -Force }
        }
    }
    Write-Done "Updated $install"
    if (Test-Path -LiteralPath $backupDirectory) { Write-Done "Backups: $backupDirectory" }
}
