function Add-CategoryEnhancements([System.IO.FileInfo]$Project) {
    $projectRoot = $Project.Directory.Parent.FullName
    $overlayPath = Join-Path $PSScriptRoot 'assets\category-enhancements.json'
    $overlay = Get-Content -Raw -Encoding UTF8 -LiteralPath $overlayPath | ConvertFrom-Json
    $pending = @{}

    foreach ($file in $overlay.Patches) {
        $path = Join-Path $projectRoot $file.Path
        $original = [IO.File]::ReadAllText($path)
        $newline = Get-NewLine $original
        $text = $original.Replace("`r`n", "`n")
        foreach ($change in $file.Changes) {
            if ($text.IndexOf($change.After, [StringComparison]::Ordinal) -ge 0) { continue }
            $index = $text.IndexOf($change.Before, [StringComparison]::Ordinal)
            if ($index -lt 0 -or $text.IndexOf($change.Before, $index + 1, [StringComparison]::Ordinal) -ge 0) {
                throw "Category enhancement could not find an unambiguous match in $($file.Path). The upstream code may have changed."
            }
            $text = $text.Remove($index, $change.Before.Length).Insert($index, $change.After)
        }
        $text = $text.Replace("`n", $newline)
        if ($text -cne $original) { $pending[$path] = $text }
    }

    foreach ($file in $overlay.NewFiles) {
        $path = Join-Path $projectRoot $file.Path
        if (Test-Path -LiteralPath $path) {
            if ([IO.File]::ReadAllText($path).Replace("`r`n", "`n") -cne $file.Content) {
                throw "Category enhancement conflicts with the existing file $($file.Path)."
            }
        } else {
            $pending[$path] = $file.Content
        }
    }

    foreach ($path in $pending.Keys) { Save-Text $path $pending[$path] }
    if ($pending.Count -gt 0) { Write-Done 'Applied category menu, viewport, and three-level grouping enhancements.' }
    return $pending.Count -gt 0
}
