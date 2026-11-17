#requires -Version 5.1
<#
    给 Stardrop 打中文增强补丁：
      1. 中文字体修复：备注列等输入框不再把中文显示成方框
      2. 右键「移动到分类」：把模组文件夹移动到 Mods 下另一个分类目录

    用法：
      apply-stardrop-patch.cmd                          自动下载最新上游、打两个补丁并编译
      apply-stardrop-patch.cmd D:\Stardrop              在指定源码目录上打补丁并编译
      apply-stardrop-patch.cmd D:\Stardrop -NoBuild     只打补丁，不编译

    补丁是幂等的：已改过的文件会跳过，可以反复对同一份源码运行。
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Source,

    [string]$Output,

    [string]$InstallDirectory,

    [switch]$NoBuild,

    [switch]$NoZip
)

$ErrorActionPreference = 'Stop'

$FontFamily = 'Microsoft YaHei'
$RepoZipUrl = 'https://codeload.github.com/Floogen/Stardrop/zip/refs/heads/development'

. (Join-Path $PSScriptRoot 'CategoryEnhancements.ps1')
. (Join-Path $PSScriptRoot 'Install-StardropBuild.ps1')

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Done([string]$Message) {
    Write-Host "    $Message" -ForegroundColor Green
}

function Write-Note([string]$Message) {
    Write-Host "    $Message" -ForegroundColor Yellow
}

function Resolve-Dotnet {
    # 只认真正带 SDK 的 dotnet：只装运行时的 dotnet 无法编译。
    $candidates = @()
    $command = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($command) { $candidates += $command.Source }
    $candidates += (Join-Path $env:USERPROFILE '.dotnet8\dotnet.exe')
    $candidates += 'C:\Program Files\dotnet\dotnet.exe'

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (-not (Test-Path $candidate)) { continue }
        $sdks = & $candidate --list-sdks 2>$null
        if ($sdks) { return $candidate }
    }

    return $null
}

function Get-LatestUpstream {
    Write-Step '下载最新上游源码 (Floogen/Stardrop development)'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $zip = Join-Path $env:TEMP "Stardrop-$stamp.zip"
    Invoke-WebRequest -Uri $RepoZipUrl -OutFile $zip -UseBasicParsing

    $destination = Join-Path $PSScriptRoot "src\Stardrop-$stamp"
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Expand-Archive -Path $zip -DestinationPath $destination -Force
    Remove-Item $zip -Force

    Write-Done "已解压到 $destination"
    return $destination
}

function Find-Project([string]$Root) {
    $project = Get-ChildItem -Path $Root -Recurse -Filter 'Stardrop.csproj' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $project) {
        throw "在 $Root 下没有找到 Stardrop.csproj，请确认这是 Stardrop 源码目录。"
    }
    return $project
}

function Save-Text([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-NewLine([string]$Text) {
    if ($Text.Contains("`r`n")) { return "`r`n" }
    return "`n"
}

function Insert-AfterLine([string]$Text, [string]$Anchor, [string]$Insert) {
    $index = $Text.IndexOf($Anchor)
    if ($index -lt 0) { return $null }
    $lineEnd = $Text.IndexOf("`n", $index)
    if ($lineEnd -lt 0) { return $Text + (Get-NewLine $Text) + $Insert }
    return $Text.Insert($lineEnd + 1, $Insert + (Get-NewLine $Text))
}

function Insert-AfterLineContaining([string]$Text, [string]$Needle, [string]$Insert) {
    $index = $Text.IndexOf($Needle)
    if ($index -lt 0) { return $null }
    $lineEnd = $Text.IndexOf([char]10, $index)
    if ($lineEnd -lt 0) { return $Text + $Insert }
    return $Text.Insert($lineEnd + 1, $Insert + (Get-NewLine $Text))
}

$ModGroupMoverSource = @'
using Stardrop.Models;
using System;
using System.IO;
using System.Linq;

namespace Stardrop.Utilities
{
    /// <summary>
    /// Moves a mod's folder into another group folder under the mods directory.
    /// Folder grouping derives a mod's group from where its folder sits, so changing
    /// groups is a directory move rather than a metadata edit.
    /// </summary>
    internal static class ModGroupMover
    {
        /// <summary>
        /// Moves <paramref name="mod"/>'s folder into <paramref name="targetGroup"/>, creating the
        /// group folder when needed and picking a free folder name on collision. When
        /// <paramref name="moveParent"/> is set the mod's parent folder is moved instead, which carries
        /// sibling component folders of the same mod along with it. The old group folder is removed when
        /// the move leaves it empty. Returns false with a user-facing reason on failure.
        /// </summary>
        internal static bool TryMove(Mod mod, string targetGroup, bool moveParent, out string? error)
        {
            error = null;

            if (String.IsNullOrWhiteSpace(Pathing.defaultModPath))
            {
                error = "the mods folder is not configured";
                return false;
            }

            if (String.IsNullOrWhiteSpace(targetGroup)
                || targetGroup.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0
                || targetGroup.Contains("..")
                || Path.IsPathRooted(targetGroup))
            {
                error = "the target group name is not valid";
                return false;
            }

            var separator = Path.DirectorySeparatorChar;
            var modsRoot = Path.GetFullPath(Pathing.defaultModPath).TrimEnd(separator, Path.AltDirectorySeparatorChar);
            var modFolder = Path.GetFullPath(mod.ModFileInfo.DirectoryName ?? String.Empty).TrimEnd(separator, Path.AltDirectorySeparatorChar);

            // Only move folders that really live inside the mods folder, so a collection mod or a bad
            // manifest path can never relocate something outside it.
            if (modFolder.StartsWith(modsRoot + separator, StringComparison.OrdinalIgnoreCase) is false)
            {
                error = "the mod is not inside the mods folder";
                return false;
            }

            var moveRoot = modFolder;
            if (moveParent)
            {
                var parent = Path.GetDirectoryName(modFolder);
                // Never lift a whole category: the parent must still be below the mods folder itself.
                if (parent is not null && String.Equals(parent, modsRoot, StringComparison.OrdinalIgnoreCase) is false)
                {
                    moveRoot = parent;
                }
            }

            var targetRoot = Path.GetFullPath(Path.Combine(modsRoot, targetGroup));
            if (targetRoot.StartsWith(modsRoot + separator, StringComparison.OrdinalIgnoreCase) is false)
            {
                error = "the target group is outside the mods folder";
                return false;
            }

            var currentParent = Path.GetDirectoryName(moveRoot);
            if (currentParent is not null && String.Equals(Path.GetFullPath(currentParent), targetRoot, StringComparison.OrdinalIgnoreCase))
            {
                // Already in the requested group.
                return true;
            }

            // Refuse to move a folder into itself or into one of its own subfolders.
            if (targetRoot.StartsWith(moveRoot + separator, StringComparison.OrdinalIgnoreCase))
            {
                error = "the target group is inside the folder being moved";
                return false;
            }

            var folderName = Path.GetFileName(moveRoot);
            var destination = Path.Combine(targetRoot, folderName);
            var suffix = 2;
            while (Directory.Exists(destination) || File.Exists(destination))
            {
                destination = Path.Combine(targetRoot, $"{folderName} ({suffix})");
                suffix++;
            }

            try
            {
                Directory.CreateDirectory(targetRoot);
                Directory.Move(moveRoot, destination);
            }
            catch (Exception exception)
            {
                error = exception.Message;
                return false;
            }

            // Clean up a group folder the move left empty, so moving the last mod out of it does not
            // leave a stray category behind. Any failure here is cosmetic and must not fail the move.
            try
            {
                var oldParent = Path.GetDirectoryName(moveRoot);
                if (oldParent is not null
                    && String.Equals(oldParent, modsRoot, StringComparison.OrdinalIgnoreCase) is false
                    && Directory.Exists(oldParent)
                    && Directory.EnumerateFileSystemEntries(oldParent).Any() is false)
                {
                    Directory.Delete(oldParent);
                }
            }
            catch
            {
            }

            return true;
        }
    }
}
'@

$MoveToGroupHandlers = @'
        /// <summary>
        /// Fills the row menu's dynamic submenus before the menu is shown, so their arrows exist and the
        /// lists reflect the state right now. Populating on SubmenuOpened would be too late: Avalonia only
        /// treats a MenuItem as a submenu while it already has items, so an empty one never opens and never
        /// raises that event.
        /// </summary>
        private void ModGridRowContextMenu_Opening(object? sender, System.ComponentModel.CancelEventArgs e)
        {
            if (sender is not ContextMenu contextMenu)
            {
                return;
            }

            // The menu is attached to the row that was right-clicked, so either the menu's own data
            // context or the placement target's carries the Mod. The grid selection is a last resort for
            // the case where the context menu is opened before its data context has been handed over.
            var mod = contextMenu.DataContext as Mod
                ?? (contextMenu.PlacementTarget as Control)?.DataContext as Mod
                ?? (this.FindControl<DataGrid>("modGrid")?.SelectedItem as Mod);

            PopulateMoveToGroupMenu(contextMenu, mod);
            PopulateCustomCategoryMenu(contextMenu, mod);
        }

        private void PopulateMoveToGroupMenu(ContextMenu contextMenu, Mod? mod)
        {
            var moveToGroupItem = contextMenu.Items.OfType<MenuItem>()
                .FirstOrDefault(item => (item.Tag as string) == "move-to-group");
            if (moveToGroupItem is null)
            {
                return;
            }

            var items = new List<MenuItem>();

            if (mod is null
                || mod.IsFromCollection
                || Program.settings.ModGroupingMethod is not (ModGrouping.Folder or ModGrouping.FolderCondensed))
            {
                items.Add(new MenuItem
                {
                    Header = Program.translation.Get("ui.main_window.menu_items.context.move_to_group_unavailable"),
                    IsEnabled = false
                });
            }
            else
            {
                var groups = _viewModel.Mods
                    .Select(candidate => candidate.RootPath)
                    .Where(group => String.IsNullOrWhiteSpace(group) is false)
                    .Where(group => String.Equals(group, mod.RootPath, StringComparison.OrdinalIgnoreCase) is false)
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .OrderBy(group => group, StringComparer.CurrentCultureIgnoreCase)
                    .ToList();

                if (groups.Count == 0)
                {
                    items.Add(new MenuItem
                    {
                        Header = Program.translation.Get("ui.main_window.menu_items.context.move_to_group_empty"),
                        IsEnabled = false
                    });
                }

                foreach (var group in groups)
                {
                    var groupItem = new MenuItem
                    {
                        Header = group,
                        Tag = group
                    };
                    groupItem.Click += async (_, _) => await MoveModToGroup(GetActionMods(mod), group);
                    items.Add(groupItem);
                }
            }

            moveToGroupItem.Items = items;
        }

        /// <summary>
        /// Builds the custom category submenu: clear assignment, the categories themselves, then the
        /// create and delete actions. Categories are directories in the store only; assigning one never
        /// touches the mods folder.
        /// </summary>
        private void PopulateCustomCategoryMenu(ContextMenu contextMenu, Mod? mod)
        {
            var customCategoryItem = contextMenu.Items.OfType<MenuItem>()
                .FirstOrDefault(item => (item.Tag as string) == "custom-category");
            if (customCategoryItem is null)
            {
                return;
            }

            var items = new List<object>();
            if (mod is null)
            {
                items.Add(new MenuItem
                {
                    Header = Program.translation.Get("ui.main_window.menu_items.context.custom_category_none"),
                    IsEnabled = false
                });
                customCategoryItem.Items = items;
                return;
            }

            var clearItem = new MenuItem
            {
                Header = Program.translation.Get("ui.main_window.menu_items.context.custom_category_none")
            };
            clearItem.Click += async (_, _) => await AssignCustomCategory(GetActionMods(mod), String.Empty);
            items.Add(clearItem);

            var categories = Program.customCategories.OrderedCategories.ToList();
            foreach (var category in categories)
            {
                var categoryItem = new MenuItem
                {
                    Header = category,
                    Tag = category
                };
                categoryItem.Click += async (_, _) => await AssignCustomCategory(GetActionMods(mod), category);
                items.Add(categoryItem);
            }

            items.Add(new Separator());

            var createItem = new MenuItem
            {
                Header = Program.translation.Get("ui.main_window.menu_items.context.custom_category_new")
            };
            createItem.Click += async (_, _) => await CreateCustomCategory(mod);
            items.Add(createItem);

            var deleteItem = new MenuItem
            {
                Header = Program.translation.Get("ui.main_window.menu_items.context.custom_category_delete")
            };
            var deleteItems = new List<MenuItem>();
            foreach (var category in categories)
            {
                var categoryItem = new MenuItem
                {
                    Header = category,
                    Tag = category
                };
                categoryItem.Click += async (_, _) => await DeleteCustomCategory(category);
                deleteItems.Add(categoryItem);
            }

            if (deleteItems.Count == 0)
            {
                deleteItems.Add(new MenuItem
                {
                    Header = Program.translation.Get("ui.main_window.menu_items.context.custom_category_empty"),
                    IsEnabled = false
                });
            }
            deleteItem.Items = deleteItems;
            items.Add(deleteItem);

            var renameItem = new MenuItem
            {
                Header = Program.translation.Get("ui.main_window.menu_items.context.custom_category_rename")
            };
            var renameItems = new List<MenuItem>();
            foreach (var category in categories)
            {
                var categoryItem = new MenuItem
                {
                    Header = category,
                    Tag = category
                };
                categoryItem.Click += async (_, _) => await RenameCustomCategory(category);
                renameItems.Add(categoryItem);
            }

            if (renameItems.Count == 0)
            {
                renameItems.Add(new MenuItem
                {
                    Header = Program.translation.Get("ui.main_window.menu_items.context.custom_category_empty"),
                    IsEnabled = false
                });
            }
            renameItem.Items = renameItems;
            items.Add(renameItem);

            customCategoryItem.Items = items;
        }

        /// <summary>
        /// Toolbar entry for batch category work: assigns one category to every selected mod, optionally
        /// pulling in every mod that shares a folder with them. Unlike the row menu this always offers the
        /// same-folder option, including for mods filed directly in a top-level category.
        /// </summary>
        private async void BatchCategory_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
        {
            var modGrid = this.FindControl<DataGrid>("modGrid");
            var selected = modGrid?.SelectedItems.OfType<Mod>().ToList() ?? new List<Mod>();
            if (selected.Count == 0)
            {
                return;
            }

            var window = new BatchCategoryWindow(selected.Count, Program.customCategories.OrderedCategories.ToList());
            window.WindowStartupLocation = WindowStartupLocation.CenterOwner;
            if (await window.ShowDialog<bool>(this) is false)
            {
                return;
            }

            var targets = new HashSet<Mod>(selected);
            if (window.IncludeSiblings)
            {
                foreach (var mod in selected)
                {
                    foreach (var folderMate in GetSameFolderMods(mod))
                    {
                        targets.Add(folderMate);
                    }
                }
            }

            await AssignCustomCategory(targets.ToList(), window.SelectedCategory);
        }

        /// <summary>
        /// Files a mod under a custom category, or clears it when the name is empty. When the mod sits in a
        /// component folder next to sibling folders of the same mod, offers to apply the category to all of
        /// them, mirroring how a folder move can take the whole parent folder. Switching into the custom
        /// grouping on first use makes the assignment visible without the user changing settings.
        /// </summary>
        private async Task AssignCustomCategory(List<Mod> mods, string category)
        {
            if (mods.Count == 0)
            {
                return;
            }

            // The folder-mate question only makes sense for one clicked mod; a multi-selection already
            // states which mods the user wants changed.
            var siblings = mods.Count == 1 ? GetSiblingMods(mods[0]) : new List<Mod>();
            var applyToSiblings = false;
            if (siblings.Count > 0)
            {
                var scopePrompt = new MessageWindow(
                    String.Format(Program.translation.Get("ui.main_window.menu_items.context.custom_category_scope"), siblings.Count),
                    Program.translation.Get("ui.main_window.menu_items.context.custom_category_all"),
                    Program.translation.Get("ui.main_window.menu_items.context.custom_category_only"));
                applyToSiblings = await scopePrompt.ShowDialog<bool>(this);
            }

            var display = String.IsNullOrEmpty(category)
                ? Program.translation.Get("ui.main_window.menu_items.context.custom_category_none")
                : Program.customCategories.Normalize(category);

            foreach (var mod in mods)
            {
                Program.customCategories.Assign(mod.UniqueId, category);
                mod.CustomCategory = display;
            }

            if (applyToSiblings)
            {
                foreach (var sibling in siblings)
                {
                    Program.customCategories.Assign(sibling.UniqueId, category);
                    sibling.CustomCategory = display;
                }
            }

            if (Program.settings.ModGroupingMethod != ModGrouping.Custom)
            {
                Program.settings.ModGroupingMethod = ModGrouping.Custom;
                _viewModel.AreModGroupsEnabled = true;
                _viewModel.UpdateDataGridGrouping();
            }
            else
            {
                _viewModel.RefreshCustomGrouping();
            }
        }

        private async Task CreateCustomCategory(Mod mod)
        {
            var namingWindow = new CategoryNamingWindow();
            namingWindow.WindowStartupLocation = WindowStartupLocation.CenterOwner;
            var name = await namingWindow.ShowDialog<string?>(this);
            if (String.IsNullOrWhiteSpace(name))
            {
                return;
            }

            var normalized = Program.customCategories.Normalize(name);
            if (String.IsNullOrEmpty(normalized))
            {
                return;
            }

            Program.customCategories.Create(normalized);
            await AssignCustomCategory(GetActionMods(mod), normalized);
            _viewModel.ReapplyCustomCategories();
        }

        private async Task DeleteCustomCategory(string category)
        {
            var confirmation = new MessageWindow(String.Format(Program.translation.Get("ui.main_window.menu_items.context.custom_category_delete_confirm"), category));
            if (await confirmation.ShowDialog<bool>(this) is false)
            {
                return;
            }

            Program.customCategories.Delete(category);
            _viewModel.ReapplyCustomCategories();
        }

        /// <summary>
        /// Renames a category, which is also how an existing category is nested under another: rename
        /// "zuzu" to "地图/zuzu" and the store rewrites the category and every assignment below it.
        /// </summary>
        private async Task RenameCustomCategory(string category)
        {
            var namingWindow = new CategoryNamingWindow(category, true);
            namingWindow.WindowStartupLocation = WindowStartupLocation.CenterOwner;
            var name = await namingWindow.ShowDialog<string?>(this);
            if (String.IsNullOrWhiteSpace(name))
            {
                return;
            }

            if (Program.customCategories.Rename(category, name) is false)
            {
                await CreateWarningWindow(Program.translation.Get("ui.main_window.menu_items.context.custom_category_rename_failed"), Program.translation.Get("internal.ok"));
                return;
            }

            _viewModel.ReapplyCustomCategories();
        }


        private async Task MoveModToGroup(List<Mod> mods, string targetGroup)
        {
            if (mods.Count == 0)
            {
                return;
            }

            var confirmationText = mods.Count == 1
                ? String.Format(Program.translation.Get("ui.main_window.menu_items.context.move_to_group_confirm"), mods[0].Name, targetGroup)
                : String.Format(Program.translation.Get("ui.main_window.menu_items.context.move_to_group_confirm_multiple"), mods.Count, targetGroup);
            var confirmation = new MessageWindow(confirmationText);
            if (await confirmation.ShowDialog<bool>(this) is false)
            {
                return;
            }

            // Ask once for the whole batch whether component folders should travel with their mods.
            var moveParent = false;
            var siblingTotal = 0;
            foreach (var mod in mods)
            {
                siblingTotal += GetSiblingMods(mod).Count;
            }

            if (siblingTotal > 0)
            {
                var scopePrompt = new MessageWindow(
                    String.Format(Program.translation.Get("ui.main_window.menu_items.context.move_to_group_scope_multiple"), siblingTotal),
                    Program.translation.Get("ui.main_window.menu_items.context.move_to_group_whole_folder"),
                    Program.translation.Get("ui.main_window.menu_items.context.move_to_group_only_mod"));
                moveParent = await scopePrompt.ShowDialog<bool>(this);
            }

            var failed = 0;
            foreach (var mod in mods)
            {
                // A previous parent-folder move can already have carried this mod, leaving its old path gone.
                if (String.IsNullOrWhiteSpace(mod.ModFileInfo.DirectoryName) || Directory.Exists(mod.ModFileInfo.DirectoryName) is false)
                {
                    continue;
                }

                var moveThisParent = moveParent && GetSiblingMods(mod).Count > 0;
                if (ModGroupMover.TryMove(mod, targetGroup, moveThisParent, out _) is false)
                {
                    failed++;
                }
            }

            // Rebuild the list from disk so the moved mods land under their new group and any group folder
            // the move emptied disappears, then restore the enabled state the current profile had.
            _viewModel.DiscoverMods(Pathing.defaultModPath);
            _viewModel.EnableModsByProfile(GetCurrentProfile());

            if (failed > 0)
            {
                await CreateWarningWindow(String.Format(Program.translation.Get("ui.main_window.menu_items.context.move_to_group_failed"), failed), Program.translation.Get("internal.ok"));
            }
        }

        /// <summary>
        /// Decides whether a move should lift the mod's parent folder, which carries sibling component
        /// folders that belong to the same mod (for example a [CP] folder next to the code folder).
        /// Only offered below category level and only when other mods really sit there; at category
        /// level the parent is the category itself, so the mod folder alone is moved.
        /// </summary>
        private async Task<bool> ShouldMoveWholeFolder(Mod mod)
        {
            var siblings = GetSiblingMods(mod);
            if (siblings.Count == 0)
            {
                return false;
            }

            var prompt = new MessageWindow(
                String.Format(Program.translation.Get("ui.main_window.menu_items.context.move_to_group_scope"), siblings.Count),
                Program.translation.Get("ui.main_window.menu_items.context.move_to_group_whole_folder"),
                Program.translation.Get("ui.main_window.menu_items.context.move_to_group_only_mod"));
            return await prompt.ShowDialog<bool>(this);
        }

        /// <summary>
        /// The mods that share the clicked mod's parent folder below category level. These are component
        /// folders of one mod (a [CP] folder beside the code folder), not separate categories, which is
        /// why a move or a category assignment can be applied to all of them at once. Empty for mods that
        /// sit directly in a category, so the category folder itself is never treated as a component set.
        /// </summary>
        private List<Mod> GetSiblingMods(Mod mod)
        {
            var siblings = new List<Mod>();
            if (String.IsNullOrWhiteSpace(Pathing.defaultModPath) || String.IsNullOrWhiteSpace(mod.ModFileInfo.DirectoryName))
            {
                return siblings;
            }

            var separator = Path.DirectorySeparatorChar;
            var modsRoot = Path.GetFullPath(Pathing.defaultModPath).TrimEnd(separator, Path.AltDirectorySeparatorChar);
            var modFolder = Path.GetFullPath(mod.ModFileInfo.DirectoryName).TrimEnd(separator, Path.AltDirectorySeparatorChar);
            var parent = Path.GetDirectoryName(modFolder);
            if (parent is null || String.Equals(parent, modsRoot, StringComparison.OrdinalIgnoreCase))
            {
                return siblings;
            }

            var relativeParent = parent.Substring(modsRoot.Length).TrimStart(separator);
            if (relativeParent.Split(separator).Length < 2)
            {
                return siblings;
            }

            foreach (var candidate in _viewModel.Mods)
            {
                if (ReferenceEquals(candidate, mod) || String.IsNullOrWhiteSpace(candidate.ModFileInfo.DirectoryName))
                {
                    continue;
                }

                if (Path.GetFullPath(candidate.ModFileInfo.DirectoryName).StartsWith(parent + separator, StringComparison.OrdinalIgnoreCase))
                {
                    siblings.Add(candidate);
                }
            }

            return siblings;
        }
'@


$PointerHelpers = @'
        /// <summary>
        /// Records which mods were selected before a right-click changed the grid selection, so context
        /// menu actions can apply to the whole selection instead of only the row under the cursor.
        /// </summary>
        private void ModGrid_PointerPressed(object? sender, PointerPressedEventArgs e)
        {
            if (e.GetCurrentPoint(null).Properties.IsRightButtonPressed is false)
            {
                _contextMods.Clear();
                _contextClickedMod = null;
                return;
            }

            _contextClickedMod = (e.Source as Control)?.DataContext as Mod;
            _contextMods = (sender as DataGrid)?.SelectedItems.OfType<Mod>().ToList() ?? new List<Mod>();
        }

        /// <summary>
        /// The mods a context menu action should apply to: the pre-right-click selection when the clicked
        /// row is part of it, otherwise just the clicked mod.
        /// </summary>
        private List<Mod> GetActionMods(Mod? clicked)
        {
            if (clicked is not null
                && _contextMods.Count > 0
                && _contextMods.Contains(clicked)
                && (_contextClickedMod is null || ReferenceEquals(clicked, _contextClickedMod)))
            {
                return _contextMods.Distinct().ToList();
            }

            return clicked is null ? new List<Mod>() : new List<Mod> { clicked };
        }

        /// <summary>
        /// Every mod sharing the same immediate parent folder as <paramref name="mod"/>, including mods
        /// filed directly in a top-level category. Used by batch category assignment, where the user
        /// explicitly asks to take the whole folder regardless of component depth.
        /// </summary>
        private List<Mod> GetSameFolderMods(Mod mod)
        {
            var matches = new List<Mod>();
            if (String.IsNullOrWhiteSpace(mod.ModFileInfo.DirectoryName))
            {
                return matches;
            }

            var parent = Path.GetDirectoryName(Path.GetFullPath(mod.ModFileInfo.DirectoryName));
            if (parent is null)
            {
                return matches;
            }

            foreach (var candidate in _viewModel.Mods)
            {
                if (String.IsNullOrWhiteSpace(candidate.ModFileInfo.DirectoryName))
                {
                    continue;
                }

                var candidateParent = Path.GetDirectoryName(Path.GetFullPath(candidate.ModFileInfo.DirectoryName));
                if (String.Equals(parent, candidateParent, StringComparison.OrdinalIgnoreCase))
                {
                    matches.Add(candidate);
                }
            }

            return matches;
        }
'@

$StateHandlers = @'
        private void ModGridMenuRow_ChangeState(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
        {
            var modGrid = this.FindControl<DataGrid>("modGrid");
            if (modGrid is null)
            {
                return;
            }
            var selectedMod = (sender as MenuItem).DataContext as Mod;
            if (selectedMod is null)
            {
                return;
            }

            EnableDisableMods(GetActionMods(selectedMod), selectedMod);
        }

        /// <summary>
        /// Enable/Disable all mods for the mod group(s) of the selected mod(s).
        /// </summary>
        ///
        /// <param name="sender">
        /// The currently selected mod of the whole mod group whose mods to enable/disable.
        /// </param>
        private void ModGridMenuRow_ChangeWholeModGroupState(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
        {
            var modGrid = this.FindControl<DataGrid>("modGrid");
            if (modGrid is null)
            {
                return;
            }
            var selectedMod = (sender as MenuItem)?.DataContext as Mod;
            if (selectedMod is null)
            {
                return;
            }

            // Select all mods of the mod group(s) whose mod 'selectedMod' is currently selected or whose mods have 
            //  been already selected previously.
            var originallySelectedModPaths = new List<string>();
            foreach (Mod mod in modGrid.SelectedItems)
            {
                originallySelectedModPaths.Add(mod.Path);
            }
            if (originallySelectedModPaths.Count is 0)
            {
                originallySelectedModPaths.Add(selectedMod.Path);
            }
            foreach (Mod mod in modGrid.Items)
            {
                if (originallySelectedModPaths.Contains(mod.Path))
                {
                    modGrid.SelectedItems.Add(mod);
                }
            }

            var groupMods = new List<Mod>();
            foreach (Mod mod in modGrid.SelectedItems)
            {
                groupMods.Add(mod);
            }

            EnableDisableMods(groupMods, selectedMod);
        }

        /// <summary>
        /// Enable/Disable the given mods, all to the state the clicked mod toggles into.
        /// </summary>
        ///
        /// <param name="mods">The mods to change, usually the pre-right-click grid selection.</param>
        /// <param name="selectedMod">The clicked mod whose current state decides the target state.</param>
        private void EnableDisableMods(List<Mod> mods, Mod? selectedMod)
        {
            if (selectedMod is null || mods.Count == 0)
            {
                return;
            }

            // Enable / disable every target mod based on the clicked mod.
            selectedMod.IsEnabled = !selectedMod.IsEnabled;
            foreach (var mod in mods)
            {
                mod.IsEnabled = selectedMod.IsEnabled;
                if (selectedMod.IsEnabled)
                {
                    EnableRequirements(mod);
                }
                else
                {
                    DisableRequirements(mod);
                }
            }

            if (Program.settings.ShouldAutomaticallySaveProfileChanges)
            {
                UpdateProfile(GetCurrentProfile());
            }
            else
            {
                _viewModel.ShowSaveProfileChanges = true;
            }
        }
'@
function Add-GlobalFontStyle([System.IO.FileInfo]$Project) {
    $path = Join-Path $Project.DirectoryName 'App.axaml'
    if (-not (Test-Path $path)) {
        $found = Get-ChildItem -Path $Project.DirectoryName -Recurse -Filter 'App.axaml' -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $found) {
            Write-Note '没有找到 App.axaml，跳过全局字体。'
            return $false
        }
        $path = $found.FullName
    }

    $text = [System.IO.File]::ReadAllText($path)
    if ($text -match [regex]::Escape($FontFamily)) {
        Write-Done 'App.axaml 已包含中文字体设置，跳过。'
        return $false
    }

    if ($text -notmatch '(?m)^[ \t]*</Application\.Styles>') {
        throw 'App.axaml 里没有 </Application.Styles>，上游结构可能变了。'
    }

    $newLine = Get-NewLine $text
    $block = @(
        "`t`t<Style Selector=`"Window`">",
        "`t`t`t<Setter Property=`"FontFamily`" Value=`"$FontFamily`" />",
        "`t`t</Style>",
        "`t`t<Style Selector=`"TextBox`">",
        "`t`t`t<Setter Property=`"FontFamily`" Value=`"$FontFamily`" />",
        "`t`t</Style>"
    ) -join $newLine
    $block += $newLine

    $updated = [regex]::Replace($text, '(?m)^([ \t]*)</Application\.Styles>', {
        param($match)
        $block + $match.Groups[1].Value + '</Application.Styles>'
    })

    Save-Text $path $updated
    Write-Done 'App.axaml：已添加 Window / TextBox 的中文字体样式。'
    return $true
}

function Add-NotesFont([System.IO.FileInfo]$Project) {
    $path = Join-Path $Project.DirectoryName 'Views\MainWindow.axaml'
    if (-not (Test-Path $path)) {
        $found = Get-ChildItem -Path $Project.DirectoryName -Recurse -Filter 'MainWindow.axaml' -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $found) {
            throw '没有找到 MainWindow.axaml。'
        }
        $path = $found.FullName
    }

    $text = [System.IO.File]::ReadAllText($path)
    $match = [regex]::Match($text, '(?s)<TextBox[^>]*Classes="notes"[^>]*/>')
    if (-not $match.Success) {
        Write-Note 'MainWindow.axaml 里没有找到 Classes="notes" 的输入框，可能上游改了备注列，请手动检查。'
        return $false
    }

    if ($match.Value -match 'FontFamily=') {
        Write-Done '备注列已指定字体，跳过。'
        return $false
    }

    $newTag = $match.Value -replace '\s*/>\s*$', " FontFamily=`"$FontFamily`" />"
    $updated = $text.Replace($match.Value, $newTag)

    Save-Text $path $updated
    Write-Done 'MainWindow.axaml：已给备注列输入框指定中文字体。'
    return $true
}

function Add-MoveToGroupFeature([System.IO.FileInfo]$Project) {
    $changed = $false

    # 1. 新增目录移动工具类
    $utilities = Join-Path $Project.DirectoryName 'Utilities'
    $moverPath = Join-Path $utilities 'ModGroupMover.cs'
    if (-not (Test-Path $moverPath)) {
        if (-not (Test-Path $utilities)) {
            throw "没有找到 Utilities 目录：$utilities"
        }
        Save-Text $moverPath $ModGroupMoverSource
        Write-Done 'Utilities/ModGroupMover.cs：已新增。'
        $changed = $true
    }
    else {
        Write-Done 'Utilities/ModGroupMover.cs 已存在，跳过。'
    }

    # 2. 右键菜单：ContextMenu 加 Opening 事件、插入「移动到分类」项
    $axamlPath = Join-Path $Project.DirectoryName 'Views\MainWindow.axaml'
    $axaml = [System.IO.File]::ReadAllText($axamlPath)
    $newLine = Get-NewLine $axaml
    $axamlChanged = $false

    $mainCode = [IO.File]::ReadAllText((Join-Path $Project.DirectoryName 'Views\MainWindow.axaml.cs'))
    $rowMenuOpensInCode = $mainCode.Contains('MenuBase.MenuOpenedEvent, ModGridRowContextMenu_Opened')
    if (!$rowMenuOpensInCode -and $axaml -notmatch 'x:Key="GridRowContextMenu"[^>]*ContextMenuOpening=') {
        $before = $axaml
        $axaml = [regex]::Replace($axaml, '(<ContextMenu\s+x:Key="GridRowContextMenu")([^>]*>)', '$1 ContextMenuOpening="ModGridRowContextMenu_Opening"$2')
        if ($axaml -eq $before) {
            throw 'MainWindow.axaml 里没有找到 GridRowContextMenu，上游结构可能变了。'
        }
        $axamlChanged = $true
        Write-Done 'MainWindow.axaml：右键菜单已挂上 ContextMenuOpening。'
    }

    if ($axaml -notmatch 'Tag="move-to-group"') {
        $deleteMarker = '<MenuItem Header="{i18n:Translate ui.main_window.menu_items.context.delete}" Click="ModGridMenuRow_Delete" />'
        $deleteIndex = $axaml.IndexOf($deleteMarker)
        if ($deleteIndex -lt 0) {
            throw 'MainWindow.axaml 里没有找到删除菜单项，无法定位「移动到分类」的插入位置。'
        }

        $cancelIndex = $axaml.IndexOf('context.cancel', $deleteIndex)
        if ($cancelIndex -lt 0) {
            throw 'MainWindow.axaml 里没有找到右键菜单的取消项。'
        }

        $lineStart = $axaml.LastIndexOf("`n", $cancelIndex) + 1
        $indentEnd = $lineStart
        while ($indentEnd -lt $axaml.Length -and ($axaml[$indentEnd] -eq ' ' -or $axaml[$indentEnd] -eq "`t")) {
            $indentEnd++
        }
        $indent = $axaml.Substring($lineStart, $indentEnd - $lineStart)

        $menuItem = $indent + '<MenuItem Tag="move-to-group" Header="{i18n:Translate ui.main_window.menu_items.context.move_to_group}" />' + $newLine
        $axaml = $axaml.Insert($lineStart, $menuItem)
        $axamlChanged = $true
        Write-Done 'MainWindow.axaml：已插入「移动到分类」菜单项。'
    }

    if ($axamlChanged) {
        Save-Text $axamlPath $axaml
        $changed = $true
    }
    else {
        Write-Done 'MainWindow.axaml 已包含「移动到分类」，跳过。'
    }

    # 3. 代码：插入菜单填充与移动处理
    $csPath = Join-Path $Project.DirectoryName 'Views\MainWindow.axaml.cs'
    $cs = [System.IO.File]::ReadAllText($csPath)
    if ($rowMenuOpensInCode -or $cs.Contains('ModGridRowContextMenu_Opening')) {
        Write-Done 'MainWindow.axaml.cs 已包含移动逻辑，跳过。'
    }
    else {
        $anchor = '        private async void ModGridMenuRow_Delete('
        if (-not $cs.Contains($anchor)) {
            throw 'MainWindow.axaml.cs 里没有找到 ModGridMenuRow_Delete，无法定位移动逻辑的插入位置。'
        }
        $cs = $cs.Replace($anchor, $MoveToGroupHandlers + $anchor)
        Save-Text $csPath $cs
        Write-Done 'MainWindow.axaml.cs：已插入移动分类逻辑。'
        $changed = $true
    }

    # 4. 文案
    $defaultKeys = @(
        '  "ui.main_window.menu_items.context.move_to_group": "Move to Group",',
        '  "ui.main_window.menu_items.context.move_to_group_confirm": "Move \"{0}\" to the group \"{1}\"? The mod''s folder will be moved on disk.",',
        '  "ui.main_window.menu_items.context.move_to_group_failed": "Failed to move the mod: {0}",',
        '  "ui.main_window.menu_items.context.move_to_group_empty": "No other groups",',
        '  "ui.main_window.menu_items.context.move_to_group_unavailable": "Not available for this grouping method",
  "ui.main_window.menu_items.context.move_to_group_scope": "This folder also holds {0} other mod(s). Move the whole folder as well?",
  "ui.main_window.menu_items.context.move_to_group_whole_folder": "Whole folder",
  "ui.main_window.menu_items.context.move_to_group_only_mod": "Only this mod",'
    ) -join $newLine
    $zhKeys = @(
        '  "ui.main_window.menu_items.context.move_to_group": "移动到分类",',
        '  "ui.main_window.menu_items.context.move_to_group_confirm": "确定把「{0}」移动到分类「{1}」吗？模组文件夹会实际移动到目标分类目录下。",',
        '  "ui.main_window.menu_items.context.move_to_group_failed": "移动模组失败：{0}",',
        '  "ui.main_window.menu_items.context.move_to_group_empty": "没有其他分类",',
        '  "ui.main_window.menu_items.context.move_to_group_unavailable": "当前分组方式下不可用",
  "ui.main_window.menu_items.context.move_to_group_scope": "该文件夹下还有 {0} 个模组，要整个文件夹一起移动吗？",
  "ui.main_window.menu_items.context.move_to_group_whole_folder": "整个文件夹",
  "ui.main_window.menu_items.context.move_to_group_only_mod": "仅当前模组",'
    ) -join $newLine

    foreach ($entry in @(
        @{ File = 'i18n\default.json'; Anchor = '  "ui.main_window.menu_items.context.delete": "Delete",'; Keys = $defaultKeys },
        @{ File = 'i18n\zh.json'; Anchor = '  "ui.main_window.menu_items.context.delete": "删除",'; Keys = $zhKeys }
    )) {
        $path = Join-Path $Project.DirectoryName $entry.File
        if (-not (Test-Path $path)) {
            Write-Note "没有找到 $($entry.File)，跳过文案。"
            continue
        }

        $text = [System.IO.File]::ReadAllText($path)
        if ($text.Contains('move_to_group')) {
            Write-Done "$($entry.File) 已包含文案，跳过。"
            continue
        }

        if (-not $text.Contains($entry.Anchor)) {
            Write-Note "$($entry.File) 里没有找到 delete 文案，跳过。"
            continue
        }

        $updated = Insert-AfterLine $text $entry.Anchor $entry.Keys
        if ($null -eq $updated) {
            Write-Note "$($entry.File) 文案插入失败，跳过。"
            continue
        }

        Save-Text $path $updated
        Write-Done "$($entry.File)：已补充文案。"
        $changed = $true
    }

    return $changed
}

function Add-ThumbnailSizeSetting([System.IO.FileInfo]$Project) {
    $changed = $false
    $root = $Project.DirectoryName

    # 1. 设置模型：新增 ModThumbnailSize
    $path = Join-Path $root 'Models\Settings.cs'
    $text = [System.IO.File]::ReadAllText($path)
    if ($text.Contains('ModThumbnailSize')) {
        Write-Done 'Models/Settings.cs 已包含缩略图大小，跳过。'
    }
    else {
        $anchor = '        public bool ShowModThumbnails { get; set; }'
        if (-not $text.Contains($anchor)) { throw 'Settings.cs 里没有找到 ShowModThumbnails。' }
        $nl = Get-NewLine $text
        $block = @(
            '        /// <summary>',
            '        /// Edge length of the mod thumbnail in the grid, in pixels. Shrinking it makes rows shorter and fits',
            '        /// more mods on screen; 125 is the size the grid used before this was configurable.',
            '        /// </summary>',
            '        public int ModThumbnailSize { get; set; } = 125;'
        ) -join $nl
        $text = $text.Replace($anchor, $anchor + $nl + $block)
        Save-Text $path $text
        Write-Done 'Models/Settings.cs：已新增 ModThumbnailSize。'
        $changed = $true
    }

    # 2. 设置窗口的 ViewModel 绑定
    $path = Join-Path $root 'ViewModels\SettingsWindowViewModel.cs'
    $text = [System.IO.File]::ReadAllText($path)
    if ($text.Contains('ModThumbnailSize')) {
        Write-Done 'SettingsWindowViewModel.cs 已包含缩略图大小，跳过。'
    }
    else {
        $anchor = '        public bool ShowModThumbnails { get { return Program.settings.ShowModThumbnails; } set { Program.settings.ShowModThumbnails = value; } }'
        if (-not $text.Contains($anchor)) { throw 'SettingsWindowViewModel.cs 里没有找到 ShowModThumbnails 绑定。' }
        $nl = Get-NewLine $text
        $block = @(
            '        public double ModThumbnailSize',
            '        {',
            '            get { return Program.settings.ModThumbnailSize; }',
            '            set { Program.settings.ModThumbnailSize = (int)Math.Clamp(value, 40, 125); }',
            '        }'
        ) -join $nl
        $text = $text.Replace($anchor, $anchor + $nl + $block)
        Save-Text $path $text
        Write-Done 'SettingsWindowViewModel.cs：已新增 ModThumbnailSize 绑定。'
        $changed = $true
    }

    # 3. 设置窗口：缩略图大小滑杆
    $path = Join-Path $root 'Views\SettingsWindow.axaml'
    $text = [System.IO.File]::ReadAllText($path)
    if ($text.Contains('modThumbnailSizeSlider')) {
        Write-Done 'SettingsWindow.axaml 已包含滑杆，跳过。'
    }
    else {
        $anchor = '					<CheckBox Name="showModThumbnails" IsChecked="{Binding ShowModThumbnails}" Content="{i18n:Translate ui.settings_window.buttons.show_mod_thumbnails}" ToolTip.Tip="{Binding ToolTip_ShowModThumbnails}" VerticalAlignment="Center" HorizontalAlignment="Left" Foreground="{DynamicResource ThemeForegroundBrush}" />'
        if (-not $text.Contains($anchor)) { throw 'SettingsWindow.axaml 里没有找到 showModThumbnails。' }
        $nl = Get-NewLine $text
        $indent = '					'
        $block = @(
            ($indent + '<StackPanel Orientation="Horizontal" VerticalAlignment="Center" HorizontalAlignment="Left" Margin="0 4 0 6" IsVisible="{Binding ShowModThumbnails}">'),
            ($indent + "`t" + '<TextBlock Text="{i18n:Translate ui.settings_window.labels.mod_thumbnail_size}" VerticalAlignment="Center" Foreground="{DynamicResource ThemeForegroundBrush}" Margin="0 0 10 0" />'),
            ($indent + "`t" + '<Slider Name="modThumbnailSizeSlider" Minimum="40" Maximum="125" TickFrequency="5" IsSnapToTickEnabled="True" Value="{Binding ModThumbnailSize, Mode=TwoWay}" Width="180" VerticalAlignment="Center" />'),
            ($indent + '</StackPanel>')
        ) -join $nl
        $text = $text.Replace($anchor, $anchor + $nl + $block)
        Save-Text $path $text
        Write-Done 'SettingsWindow.axaml：已添加缩略图大小滑杆。'
        $changed = $true
    }

    # 4. 主窗口 ViewModel
    $path = Join-Path $root 'ViewModels\MainWindowViewModel.cs'
    $text = [System.IO.File]::ReadAllText($path)
    if ($text.Contains('ModThumbnailSize')) {
        Write-Done 'MainWindowViewModel.cs 已包含缩略图大小，跳过。'
    }
    else {
        $anchor = '        public bool ShowModThumbnails { get { return _showModThumbnails; } set { this.RaiseAndSetIfChanged(ref _showModThumbnails, value); } }'
        if (-not $text.Contains($anchor)) { throw 'MainWindowViewModel.cs 里没有找到 ShowModThumbnails。' }
        $nl = Get-NewLine $text
        $block = @(
            '        /// <summary>',
            '        /// Edge length of the thumbnails in the grid. Kept on the view model so changing it in settings can',
            '        /// resize the rows without reloading the mod list.',
            '        /// </summary>',
            '        public double ModThumbnailSize { get { return _modThumbnailSize; } set { this.RaiseAndSetIfChanged(ref _modThumbnailSize, value); } }',
            '        private double _modThumbnailSize = Program.settings.ModThumbnailSize;'
        ) -join $nl
        $text = $text.Replace($anchor, $anchor + $nl + $block)
        Save-Text $path $text
        Write-Done 'MainWindowViewModel.cs：已新增 ModThumbnailSize。'
        $changed = $true
    }

    # 5. 主窗口缩略图尺寸绑定
    $path = Join-Path $root 'Views\MainWindow.axaml'
    $text = [System.IO.File]::ReadAllText($path)
    if ($text.Contains('DataContext.ModThumbnailSize')) {
        Write-Done 'MainWindow.axaml 缩略图已绑定大小，跳过。'
    }
    else {
        $anchor = '<Image Height="125" Width="125"'
        if (-not $text.Contains($anchor)) {
            Write-Note 'MainWindow.axaml 里没有找到 125x125 的缩略图，可能上游改了尺寸，请手动检查。'
        }
        else {
            $text = $text.Replace($anchor, '<Image Height="{Binding $parent[DataGrid].DataContext.ModThumbnailSize}" Width="{Binding $parent[DataGrid].DataContext.ModThumbnailSize}" MaxHeight="125" MaxWidth="125"')
            Save-Text $path $text
            Write-Done 'MainWindow.axaml：缩略图尺寸已改为绑定设置。'
            $changed = $true
        }
    }

    # 6. 设置窗口关闭后把新尺寸同步到主窗口
    $path = Join-Path $root 'Views\MainWindow.axaml.cs'
    $text = [System.IO.File]::ReadAllText($path)
    if ($text.Contains('ModThumbnailSize = Program.settings.ModThumbnailSize')) {
        Write-Done 'MainWindow.axaml.cs 已同步缩略图大小，跳过。'
    }
    else {
        $anchor = '                _viewModel.ShowModThumbnails = Program.settings.ShowModThumbnails;'
        if (-not $text.Contains($anchor)) { throw 'MainWindow.axaml.cs 里没有找到 ShowModThumbnails 同步。' }
        $nl = Get-NewLine $text
        $text = $text.Replace($anchor, $anchor + $nl + '                _viewModel.ModThumbnailSize = Program.settings.ModThumbnailSize;')
        Save-Text $path $text
        Write-Done 'MainWindow.axaml.cs：设置关闭后同步缩略图大小。'
        $changed = $true
    }

    # 7. 文案
    foreach ($entry in @(
        @{ File = 'i18n\default.json'; Anchor = '  "ui.settings_window.labels.miscellaneous": "Miscellaneous",'; Key = '  "ui.settings_window.labels.mod_thumbnail_size": "Thumbnail Size",' },
        @{ File = 'i18n\zh.json'; Anchor = '  "ui.settings_window.labels.miscellaneous": "杂项",'; Key = '  "ui.settings_window.labels.mod_thumbnail_size": "缩略图大小",' }
    )) {
        $path = Join-Path $root $entry.File
        if (-not (Test-Path $path)) { continue }
        $text = [System.IO.File]::ReadAllText($path)
        if ($text.Contains('ui.settings_window.labels.mod_thumbnail_size')) {
            Write-Done "$($entry.File) 已包含缩略图大小文案，跳过。"
            continue
        }
        if (-not $text.Contains($entry.Anchor)) {
            Write-Note "$($entry.File) 里没有找到 miscellaneous 文案，跳过。"
            continue
        }
        $text = $text.Replace($entry.Anchor, $entry.Anchor + (Get-NewLine $text) + $entry.Key)
        Save-Text $path $text
        Write-Done "$($entry.File)：已补充缩略图大小文案。"
        $changed = $true
    }

    return $changed
}

function Add-CustomCategories([System.IO.FileInfo]$Project) {
    $changed = $false
    $root = $Project.DirectoryName
    $nl = "`r`n"
    $assets = Join-Path $PSScriptRoot 'assets'

    # 1. New files: the category store and the naming dialog
    foreach ($pair in @(
        @{ Source = 'CustomCategoryStore.cs'; Destination = 'Models\CustomCategoryStore.cs' },
        @{ Source = 'CategoryNamingWindow.axaml'; Destination = 'Views\CategoryNamingWindow.axaml' },
        @{ Source = 'CategoryNamingWindow.axaml.cs'; Destination = 'Views\CategoryNamingWindow.axaml.cs' }
    )) {
        $target = Join-Path $root $pair.Destination
        if (Test-Path $target) {
            Write-Done "$($pair.Destination) already exists, skipped."
            continue
        }

        $source = Join-Path $assets $pair.Source
        if (-not (Test-Path $source)) {
            throw "Missing asset file: $source"
        }

        Copy-Item -LiteralPath $source -Destination $target
        Write-Done "$($pair.Destination): added."
        $changed = $true
    }

    # 2. Category store path
    $path = Join-Path $root 'Utilities\Pathing.cs'
    $text = [System.IO.File]::ReadAllText($path)
    if ($text.Contains('GetCustomCategoriesPath')) {
        Write-Done 'Pathing.cs already has the category path, skipped.'
    }
    else {
        $nl = Get-NewLine $text
        $updated = [regex]::Replace($text, '(?s)(internal static string GetSettingsPath\(\)\s*\{\s*return Path\.Combine\(defaultHomePath, "Settings\.json"\);\s*\})', {
            param($match)
            $block = @(
                '',
                '        internal static string GetCustomCategoriesPath()',
                '        {',
                '            return Path.Combine(defaultHomePath, "CustomCategories.json");',
                '        }'
            ) -join $nl
            $match.Groups[1].Value + $block
        })
        if ($updated -eq $text) {
            throw 'GetSettingsPath not matched in Pathing.cs.'
        }
        Save-Text $path $updated
        Write-Done 'Pathing.cs: added GetCustomCategoriesPath.'
        $changed = $true
    }

    # 3. Program: static store and load
    $path = Join-Path $root 'Program.cs'
    $text = [System.IO.File]::ReadAllText($path)
    $nl = Get-NewLine $text
    if ($text.Contains('customCategories')) {
        Write-Done 'Program.cs already has the category store, skipped.'
    }
    else {
        $text = $text.Replace(
            '        internal static AssetLoader assetLoader = new AssetLoader();',
            '        internal static AssetLoader assetLoader = new AssetLoader();' + $nl +
            '        /// <summary>User-defined categories, stored outside the mods folder so they never move files.</summary>' + $nl +
            '        internal static Models.CustomCategoryStore customCategories = new Models.CustomCategoryStore();')
        $text = $text.Replace(
            '            Pathing.SetHomePath(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData));',
            '            Pathing.SetHomePath(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData));' + $nl + $nl +
            '            // Categories live beside the settings, not in the mods folder; load them before any Mod is built.' + $nl +
            '            customCategories = Models.CustomCategoryStore.Load(Pathing.GetCustomCategoriesPath());')
        Save-Text $path $text
        Write-Done 'Program.cs: added the category store and its load.'
        $changed = $true
    }

    # 4. Mod: category property, two-level grouping fields and constructor assignment
    $path = Join-Path $root 'Models\Mod.cs'
    $text = [System.IO.File]::ReadAllText($path)
    $nl = Get-NewLine $text
    if ($text.Contains('CustomCategoryRoot')) {
        Write-Done 'Mod.cs already has the custom category, skipped.'
    }
    else {
        $noteLine = '        public string Note { get { return _note; } set { _note = value; NotifyPropertyChanged("Note"); } }'
        if (-not $text.Contains($noteLine)) { throw 'Note property not found in Mod.cs.' }
        $propertyBlock = @(
            '        /// <summary>',
            '        /// The user-defined category this mod is filed under, or the translated "uncategorized" label.',
            '        /// Set from Program.customCategories, so it follows the mod unique ID rather than its folder.',
            '        /// </summary>',
            '        private string _customCategory { get; set; }',
            '        public string CustomCategory',
            '        {',
            '            get { return _customCategory; }',
            '            set',
            '            {',
            '                _customCategory = value;',
            '                UpdateCustomCategoryTree();',
            '                NotifyPropertyChanged(nameof(CustomCategory));',
            '            }',
            '        }',
            '        /// <summary>Top-level part of the custom category, used as the first grid group level.</summary>',
            '        private string _customCategoryRoot { get; set; }',
            '        public string CustomCategoryRoot { get { return _customCategoryRoot; } }',
            '        /// <summary>',
            '        /// Everything below the top-level category, or a translated "direct" label for mods filed on a',
            '        /// top-level category itself. The grid groups on this as the second level.',
            '        /// </summary>',
            '        private string _customCategorySub { get; set; }',
            '        public string CustomCategorySub { get { return _customCategorySub; } }'
        ) -join $nl
        $text = $text.Replace($noteLine, $noteLine + $nl + $propertyBlock)

        $ctorLine = '            UniqueId = uniqueId;'
        if (-not $text.Contains($ctorLine)) { throw 'UniqueId assignment not found in Mod.cs.' }
        $ctorBlock = @(
            '            _customCategory = String.IsNullOrEmpty(Program.customCategories.Get(uniqueId))',
            '                ? Program.translation.Get("ui.main_window.menu_items.context.custom_category_none")',
            '                : Program.customCategories.Get(uniqueId);',
            '            UpdateCustomCategoryTree();'
        ) -join $nl
        $text = $text.Replace($ctorLine, $ctorLine + $nl + $ctorBlock)

        $notifyAnchor = '        internal void NotifyPropertyChanged([CallerMemberName] String propertyName = "")'
        if (-not $text.Contains($notifyAnchor)) { throw 'NotifyPropertyChanged not found in Mod.cs.' }
        $treeMethod = @(
            '        /// <summary>',
            '        /// Splits the custom category into the two levels the grid groups on: the top-level category',
            '        /// and the remainder below it. A mod filed on a top-level category has no remainder, so it gets',
            '        /// a translated "direct" label instead of an empty group header.',
            '        /// </summary>',
            '        private void UpdateCustomCategoryTree()',
            '        {',
            '            var parts = (_customCategory ?? String.Empty).Split(CustomCategoryStore.Separator);',
            '            _customCategoryRoot = parts.Length > 0 ? parts[0] : String.Empty;',
            '            _customCategorySub = parts.Length > 1',
            '                ? String.Join(CustomCategoryStore.Separator.ToString(), parts.Skip(1))',
            '                : Program.translation.Get("ui.main_window.menu_items.context.custom_category_direct");',
            '',
            '            NotifyPropertyChanged(nameof(CustomCategoryRoot));',
            '            NotifyPropertyChanged(nameof(CustomCategorySub));',
            '        }',
            '',
            ''
        ) -join $nl
        $text = $text.Replace($notifyAnchor, $treeMethod + $notifyAnchor)

        Save-Text $path $text
        Write-Done 'Models/Mod.cs: added the custom category.'
        $changed = $true
    }

    # 5. Grouping enum value
    $path = Join-Path $root 'Models\Data\Enums\ModGrouping.cs'
    $text = [System.IO.File]::ReadAllText($path)
    if ($text.Contains('Custom Categories')) {
        Write-Done 'ModGrouping.cs already has Custom, skipped.'
    }
    else {
        $nl = Get-NewLine $text
        $updated = [regex]::Replace($text, '(?m)(        \[Description\("Folder \(Condensed\)"\)\]\r?\n        FolderCondensed)', {
            param($match)
            $match.Groups[1].Value + ',' + $nl + '        [Description("Custom Categories")]' + $nl + '        Custom'
        })
        if ($updated -eq $text) { throw 'FolderCondensed not matched in ModGrouping.cs.' }
        Save-Text $path $updated
        Write-Done 'ModGrouping.cs: added Custom.'
        $changed = $true
    }

    # 6. View model: grouping descriptions, two-level custom grouping and helpers
    $path = Join-Path $root 'ViewModels\MainWindowViewModel.cs'
    $text = [System.IO.File]::ReadAllText($path)
    $nl = Get-NewLine $text
    if ($text.Contains('_customCategoryRootGrouping')) {
        Write-Done 'MainWindowViewModel.cs already has the custom grouping, skipped.'
    }
    else {
        $fieldLine = '        private DataGridPathGroupDescription _frameworkGrouping = new DataGridPathGroupDescription(nameof(Mod.FrameworkID));'
        if (-not $text.Contains($fieldLine)) { throw 'Framework grouping field not found in MainWindowViewModel.cs.' }
        $text = $text.Replace($fieldLine, $fieldLine + $nl +
            '        private DataGridPathGroupDescription _customCategoryRootGrouping = new DataGridPathGroupDescription(nameof(Mod.CustomCategoryRoot));' + $nl +
            '        private DataGridPathGroupDescription _customCategorySubGrouping = new DataGridPathGroupDescription(nameof(Mod.CustomCategorySub));')

        $newGroupingMethod = @(
            '        internal void UpdateDataGridGrouping()',
            '        {',
            '            if (DataView is not null)',
            '            {',
            '                // Custom categories group in two levels (top-level category, then the subcategory), so',
            '                // this collects a list instead of a single description.',
            '                var desiredGroupings = new List<DataGridPathGroupDescription>();',
            '                switch (Program.settings.ModGroupingMethod)',
            '                {',
            '                    case ModGrouping.Folder:',
            '                        desiredGroupings.Add(_modPathGrouping);',
            '                        break;',
            '                    case ModGrouping.FolderCondensed:',
            '                        desiredGroupings.Add(_rootPathGrouping);',
            '                        break;',
            '                    case ModGrouping.ContentPack:',
            '                        desiredGroupings.Add(_frameworkGrouping);',
            '                        break;',
            '                    case ModGrouping.Custom:',
            '                        desiredGroupings.Add(_customCategoryRootGrouping);',
            '                        desiredGroupings.Add(_customCategorySubGrouping);',
            '                        break;',
            '                }',
            '',
            '                foreach (var grouping in DataView.GroupDescriptions.OfType<DataGridPathGroupDescription>().ToList())',
            '                {',
            '                    if (desiredGroupings.Contains(grouping) is false)',
            '                    {',
            '                        DataView.GroupDescriptions.Remove(grouping);',
            '                    }',
            '                }',
            '',
            '                foreach (var grouping in desiredGroupings)',
            '                {',
            '                    if (DataView.GroupDescriptions.Contains(grouping) is false)',
            '                    {',
            '                        DataView.GroupDescriptions.Add(grouping);',
            '                    }',
            '                }',
            '',
            '                HandleModGroupingSorting();',
            '            }',
            '        }',
            ''
        ) -join $nl

        $groupingPattern = '(?s)        internal void UpdateDataGridGrouping\(\).*?HandleModGroupingSorting\(\);\r?\n            \}\r?\n        \}'
        $updated = [regex]::Replace($text, $groupingPattern, { param($match) $newGroupingMethod })
        if ($updated -eq $text) { throw 'UpdateDataGridGrouping could not be replaced in MainWindowViewModel.cs.' }
        $text = $updated

        $helperAnchor = '        internal void UpdateDataGridGrouping()'
        if (-not $text.Contains($helperAnchor)) { throw 'UpdateDataGridGrouping not found in MainWindowViewModel.cs.' }
        $helpers = @(
            '        /// <summary>',
            '        /// Re-reads every mod custom category from the store and rebuilds the grid groups. Used after a',
            '        /// category is created or deleted, where more than the clicked mod can be affected.',
            '        /// </summary>',
            '        internal void ReapplyCustomCategories()',
            '        {',
            '            var uncategorized = Program.translation.Get("ui.main_window.menu_items.context.custom_category_none");',
            '            foreach (var mod in Mods)',
            '            {',
            '                var category = Program.customCategories.Get(mod.UniqueId);',
            '                mod.CustomCategory = String.IsNullOrEmpty(category) ? uncategorized : category;',
            '            }',
            '',
            '            RefreshCustomGrouping();',
            '        }',
            '',
            '        /// <summary>',
            '        /// Rebuilds the grid groups after a mod custom category changed, so it moves to its new group',
            '        /// without a full mod rescan.',
            '        /// </summary>',
            '        internal void RefreshCustomGrouping()',
            '        {',
            '            if (Program.settings.ModGroupingMethod == ModGrouping.Custom)',
            '            {',
            '                DataView?.Refresh();',
            '            }',
            '        }',
            '',
            ''
        ) -join $nl
        $text = $text.Replace($helperAnchor, $helpers + $helperAnchor)

        Save-Text $path $text
        Write-Done 'MainWindowViewModel.cs: added the two-level custom grouping.'
        $changed = $true
    }

    # 7. Settings: the grouping option
    $path = Join-Path $root 'Views\SettingsWindow.axaml.cs'
    $text = [System.IO.File]::ReadAllText($path)
    if ($text.Contains('ModGrouping.Custom')) {
        Write-Done 'SettingsWindow.axaml.cs already has the custom option, skipped.'
    }
    else {
        $nl = Get-NewLine $text
        $anchor = '                { ModGrouping.FolderCondensed, Program.translation.Get("ui.settings_window.mod_grouping.folder_condensed") }'
        if (-not $text.Contains($anchor)) { throw 'FolderCondensed option not found in SettingsWindow.axaml.cs.' }
        $text = $text.Replace($anchor, $anchor + ',' + $nl + '                { ModGrouping.Custom, Program.translation.Get("ui.settings_window.mod_grouping.custom") }')
        Save-Text $path $text
        Write-Done 'SettingsWindow.axaml.cs: added the custom grouping option.'
        $changed = $true
    }

    # 8. Row menu item
    $path = Join-Path $root 'Views\MainWindow.axaml'
    $text = [System.IO.File]::ReadAllText($path)
    if ($text.Contains('Tag="custom-category"')) {
        Write-Done 'MainWindow.axaml already has the custom category item, skipped.'
    }
    else {
        $anchor = '<MenuItem Tag="move-to-group" Header="{i18n:Translate ui.main_window.menu_items.context.move_to_group}" />'
        if (-not $text.Contains($anchor)) { throw 'Move to group menu item not found in MainWindow.axaml.' }
        $nl = Get-NewLine $text
        $indent = '						'
        $text = $text.Replace($anchor, $anchor + $nl + $indent + '<MenuItem Tag="custom-category" Header="{i18n:Translate ui.main_window.menu_items.context.custom_category}" />')
        Save-Text $path $text
        Write-Done 'MainWindow.axaml: added the Custom Category item.'
        $changed = $true
    }

    # 8b. Show group item counts on every group header
    $path = Join-Path $root 'Views\MainWindow.axaml'
    $text = [System.IO.File]::ReadAllText($path)
    if ($text.Contains('IsItemCountVisible')) {
        Write-Done 'MainWindow.axaml already shows group counts, skipped.'
    }
    else {
        $nl = Get-NewLine $text
        $updated = [regex]::Replace($text, '(?s)(<Style Selector="DataGridRowGroupHeader">.*?)(\s*</Style>)', {
            param($match)
            $match.Groups[1].Value + $nl + "`t`t`t<Setter Property=`"IsItemCountVisible`" Value=`"True`"/>" + $match.Groups[2].Value
        })
        if ($updated -eq $text) { throw 'DataGridRowGroupHeader style not found in MainWindow.axaml.' }
        Save-Text $path $updated
        Write-Done 'MainWindow.axaml: group headers now show item counts.'
        $changed = $true
    }
    # 8c. Cap long submenus so the category list scrolls instead of running off screen
    $path = Join-Path $root 'App.axaml'
    $text = [System.IO.File]::ReadAllText($path)
    if ($text.Contains('menuscroller')) {
        Write-Done 'App.axaml already caps submenu height, skipped.'
    }
    else {
        $nl = Get-NewLine $text
        $style = @(
            "`t`t<Style Selector=`"ScrollViewer.menuscroller`">",
            "`t`t`t<Setter Property=`"MaxHeight`" Value=`"360`"/>",
            "`t`t`t<Setter Property=`"VerticalScrollBarVisibility`" Value=`"Auto`"/>",
            "`t`t`t<Setter Property=`"AllowAutoHide`" Value=`"False`"/>",
            "`t`t</Style>"
        ) -join $nl
        $updated = [regex]::Replace($text, '(?m)^([ \t]*)</Application\.Styles>', { param($m) $style + $nl + $m.Groups[1].Value + '</Application.Styles>' })
        if ($updated -eq $text) { throw 'No </Application.Styles> in App.axaml.' }
        Save-Text $path $updated
        Write-Done 'App.axaml: long submenus now scroll.'
        $changed = $true
    }
    # 9. Translation strings: context menu and the naming dialog
    $defaultKeys = @(
        '  "ui.main_window.menu_items.context.custom_category": "Custom Category",',
        '  "ui.main_window.menu_items.context.custom_category_none": "Uncategorized",',
        '  "ui.main_window.menu_items.context.custom_category_new": "New Category...",',
        '  "ui.main_window.menu_items.context.custom_category_delete": "Delete Category",',
        '  "ui.main_window.menu_items.context.custom_category_delete_confirm": "Delete the category \"{0}\"? Mods in it become uncategorized.",',
        '  "ui.main_window.menu_items.context.custom_category_empty": "No categories",'
        '  "ui.main_window.menu_items.context.custom_category_scope": "This folder also holds {0} other mod(s). Apply the category to all of them?",'
        '  "ui.main_window.menu_items.context.custom_category_all": "All in this folder",'
        '  "ui.main_window.menu_items.context.custom_category_only": "Only this mod",'
        '  "ui.main_window.menu_items.context.custom_category_direct": "Direct mods",'
        '  "ui.main_window.menu_items.context.custom_category_rename": "Rename Category",'
        '  "ui.main_window.menu_items.context.custom_category_rename_failed": "Could not rename the category. The new name is empty, already used, or the category no longer exists.",'
        '  "ui.category_window.rename_title": "Rename Category",',
        '  "ui.category_window.title": "New Category",',
        '  "ui.category_window.label": "Category name (use \\ between levels to nest, e.g. Items\\Food):",'
    ) -join $nl
    $zhKeys = @(
        '  "ui.main_window.menu_items.context.custom_category": "自定义分类",',
        '  "ui.main_window.menu_items.context.custom_category_none": "未分类",',
        '  "ui.main_window.menu_items.context.custom_category_new": "新建分类...",',
        '  "ui.main_window.menu_items.context.custom_category_delete": "删除分类",',
        '  "ui.main_window.menu_items.context.custom_category_delete_confirm": "删除分类「{0}」？其中的模组会变成未分类。",',
        '  "ui.main_window.menu_items.context.custom_category_empty": "还没有分类",'
        '  "ui.main_window.menu_items.context.custom_category_scope": "该文件夹下还有 {0} 个模组，要一起设置分类吗？",'
        '  "ui.main_window.menu_items.context.custom_category_all": "文件夹内全部",'
        '  "ui.main_window.menu_items.context.custom_category_only": "仅当前模组",'
        '  "ui.main_window.menu_items.context.custom_category_direct": "直属模组",'
        '  "ui.main_window.menu_items.context.custom_category_rename": "重命名分类",'
        '  "ui.main_window.menu_items.context.custom_category_rename_failed": "重命名失败：名称为空、已存在，或分类不存在。",'
        '  "ui.category_window.rename_title": "重命名分类",',
        '  "ui.category_window.title": "新建分类",',
        '  "ui.category_window.label": "分类名称（用 \\ 分层，例如 物品\\食物）：",'
    ) -join $nl

    foreach ($entry in @(
        @{ File = 'i18n\default.json'; Keys = $defaultKeys; Key = '  "ui.settings_window.mod_grouping.custom": "Custom Categories",' },
        @{ File = 'i18n\zh.json'; Keys = $zhKeys; Key = '  "ui.settings_window.mod_grouping.custom": "自定义分类",' }
    )) {
        $path = Join-Path $root $entry.File
        if (-not (Test-Path $path)) { continue }
        $text = [System.IO.File]::ReadAllText($path)
        if ($text.Contains('custom_category')) {
            Write-Done "$($entry.File) already has the custom strings, skipped."
        }
        else {
            $updated = Insert-AfterLineContaining $text '"ui.main_window.menu_items.context.move_to_group_only_mod":' $entry.Keys
            if ($null -eq $updated) { throw "No move_to_group_only_mod line in $($entry.File)." }
            $text = $updated
            Write-Done "$($entry.File): added the custom category strings."
            $changed = $true
        }

        if ($text.Contains('mod_grouping.custom')) {
            Write-Done "$($entry.File) already has the grouping label, skipped."
        }
        else {
            $updated = Insert-AfterLineContaining $text '"ui.settings_window.mod_grouping.folder_condensed":' $entry.Key
            if ($null -eq $updated) { throw "No folder_condensed line in $($entry.File)." }
            $text = $updated
            Save-Text $path $text
            Write-Done "$($entry.File): added the custom grouping label."
            $changed = $true
        }
    }

    return $changed
}

function Add-MultiSelectAndBatch([System.IO.FileInfo]$Project) {
    $changed = $false
    $root = $Project.DirectoryName

    # 1. Batch category dialog
    foreach ($pair in @(
        @{ Source = 'BatchCategoryWindow.axaml'; Destination = 'Views\BatchCategoryWindow.axaml' },
        @{ Source = 'BatchCategoryWindow.axaml.cs'; Destination = 'Views\BatchCategoryWindow.axaml.cs' }
    )) {
        $target = Join-Path $root $pair.Destination
        if (Test-Path $target) {
            Write-Done "$($pair.Destination) already exists, skipped."
            continue
        }

        $source = Join-Path $PSScriptRoot ('assets\' + $pair.Source)
        if (-not (Test-Path $source)) { throw "Missing asset file: $source" }
        Copy-Item -LiteralPath $source -Destination $target
        Write-Done "$($pair.Destination): added."
        $changed = $true
    }

    # 2. Code behind: selection snapshot, multi-select state changes and batch handler
    $path = Join-Path $root 'Views\MainWindow.axaml.cs'
    $text = [System.IO.File]::ReadAllText($path)
    if ($text.Contains('ModGrid_PointerPressed')) {
        Write-Done 'MainWindow.axaml.cs already has multi-select support, skipped.'
    }
    else {
        $nl = Get-NewLine $text

        $constAnchor = '        private const string _smapiConfigOverrideName = "SMAPI-config.json";'
        if (-not $text.Contains($constAnchor)) { throw 'SMAPI config override constant not found in MainWindow.axaml.cs.' }
        $fields = @(
            '        /// <summary>',
            '        /// Snapshot of the grid selection taken when the right mouse button goes down. The grid changes',
            '        /// its selection while handling that press, so by the time a context menu item runs this is the',
            '        /// only record of what was selected before the menu opened.',
            '        /// </summary>',
            '        private List<Mod> _contextMods = new List<Mod>();',
            '        private Mod? _contextClickedMod;'
        ) -join $nl
        $text = $text.Replace($constAnchor, $constAnchor + $nl + $fields)

        $changeStateMarker = '        private void ModGridMenuRow_ChangeState(object? sender, Avalonia.Interactivity.RoutedEventArgs e)'
        $openFolderMarker = '        private void ModGridMenuRow_OpenFolderPath(object? sender, Avalonia.Interactivity.RoutedEventArgs e)'
        $replacePattern = '(?s)        private void ModGridMenuRow_ChangeState\(.*?(?=' + [regex]::Escape($openFolderMarker) + ')'
        $updated = [regex]::Replace($text, $replacePattern, { param($match) $StateHandlers.TrimEnd() + $nl + $nl })
        if ($updated -eq $text) { throw 'ChangeState block could not be replaced in MainWindow.axaml.cs.' }
        $text = $updated

        if (-not $text.Contains($changeStateMarker)) { throw 'ChangeState method lost during replacement.' }
        $text = $text.Replace($changeStateMarker, $PointerHelpers.TrimEnd() + $nl + $nl + $changeStateMarker)

        Save-Text $path $text
        Write-Done 'MainWindow.axaml.cs: multi-select and batch handlers added.'
        $changed = $true
    }

    # 3. Main window markup: hook the grid pointer press and add the toolbar button
    $path = Join-Path $root 'Views\MainWindow.axaml'
    $text = [System.IO.File]::ReadAllText($path)
    $xamlChanged = $false

    $mainCode = [IO.File]::ReadAllText((Join-Path $root 'Views\MainWindow.axaml.cs'))
    if (!$mainCode.Contains('AddHandler(InputElement.PointerPressedEvent, ModGrid_PointerPressed, RoutingStrategies.Tunnel)') -and
        $text -notmatch 'Name="modGrid"[^>]*PointerPressed=') {
        $before = $text
        $text = $text.Replace('<DataGrid Name="modGrid" ', '<DataGrid Name="modGrid" PointerPressed="ModGrid_PointerPressed" ')
        if ($text -eq $before) { throw 'modGrid DataGrid tag not found in MainWindow.axaml.' }
        $xamlChanged = $true
    }

    if ($text -notmatch 'Name="batchCategoryButton"') {
        $anchor = '<Button Name="saveProfileChanges"'
        $index = $text.IndexOf($anchor)
        if ($index -lt 0) { throw 'saveProfileChanges button not found in MainWindow.axaml.' }
        $nl = Get-NewLine $text
        $lineStart = $text.LastIndexOf("`n", $index) + 1
        $indentEnd = $lineStart
        while ($indentEnd -lt $text.Length -and ($text[$indentEnd] -eq ' ' -or $text[$indentEnd] -eq "`t")) { $indentEnd++ }
        $indent = $text.Substring($lineStart, $indentEnd - $lineStart)

        $lineEnd = $text.IndexOf("`n", $index)
        $button = $indent + '<Button Name="batchCategoryButton" Content="{i18n:Translate ui.main_window.buttons.batch_category}" Click="BatchCategory_Click" VerticalAlignment="Center" Margin="5 0 0 0" Foreground="{DynamicResource ThemeForegroundBrush}" Background="Transparent" BorderBrush="{DynamicResource HighlightBrush}"/>' + $nl
        $text = $text.Insert($lineEnd + 1, $button)
        $xamlChanged = $true
    }

    if ($xamlChanged) {
        Save-Text $path $text
        Write-Done 'MainWindow.axaml: batch category button and pointer hook added.'
        $changed = $true
    }
    else {
        Write-Done 'MainWindow.axaml already has the batch button and pointer hook, skipped.'
    }

    # 4. Strings
    $defaultKeys = @(
        '  "ui.main_window.buttons.batch_category": "Batch Category",',
        '  "ui.batch_category.title": "Batch Category",',
        '  "ui.batch_category.summary": "Assign a category to the {0} selected mod(s).",',
        '  "ui.batch_category.category_label": "Category:",',
        '  "ui.batch_category.include_siblings": "Also include other mods in the same folder(s)",',
        '  "ui.main_window.menu_items.context.move_to_group_confirm_multiple": "Move {0} mods to the group \"{1}\"?",',
        '  "ui.main_window.menu_items.context.move_to_group_scope_multiple": "{0} other mod(s) sit in the same folders as the selected mods. Move the whole folders as well?",'
    ) -join "`r`n"
    $zhKeys = @(
        '  "ui.main_window.buttons.batch_category": "批量分类",',
        '  "ui.batch_category.title": "批量分类",',
        '  "ui.batch_category.summary": "为选中的 {0} 个模组设置分类。",',
        '  "ui.batch_category.category_label": "分类：",',
        '  "ui.batch_category.include_siblings": "同时包含同文件夹下的其他模组",',
        '  "ui.main_window.menu_items.context.move_to_group_confirm_multiple": "把 {0} 个模组移动到分类「{1}」？",',
        '  "ui.main_window.menu_items.context.move_to_group_scope_multiple": "选中的模组所在文件夹下还有 {0} 个其他模组，要连同整个文件夹一起移动吗？",'
    ) -join "`r`n"

    foreach ($entry in @(
        @{ File = 'i18n\default.json'; Keys = $defaultKeys },
        @{ File = 'i18n\zh.json'; Keys = $zhKeys }
    )) {
        $path = Join-Path $root $entry.File
        if (-not (Test-Path $path)) { continue }
        $text = [System.IO.File]::ReadAllText($path)
        if ($text.Contains('ui.batch_category')) {
            Write-Done "$($entry.File) already has the batch strings, skipped."
            continue
        }

        $updated = Insert-AfterLineContaining $text '"ui.main_window.menu_items.context.custom_category_empty":' $entry.Keys
        if ($null -eq $updated) { throw "No custom_category_empty line in $($entry.File)." }
        Save-Text $path $updated
        Write-Done "$($entry.File): added the batch strings."
        $changed = $true
    }

    return $changed
}

function Publish-Stardrop([System.IO.FileInfo]$Project, [string]$Target) {


    $dotnet = Resolve-Dotnet
    if (-not $dotnet) {
        Write-Note '没有找到带 SDK 的 dotnet。要编译请先安装 .NET 8 SDK（winget install Microsoft.DotNet.SDK.8），或加 -NoBuild 只打补丁。'
        return $false
    }

    New-Item -ItemType Directory -Force -Path $Target | Out-Null

    Write-Step '编译并发布 (win-x64, self-contained)'
    $pathMap = "-p:PathMap=$($Project.Directory.Parent.FullName)=/_/stardrop"
    & $dotnet publish $Project.FullName $pathMap -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o $Target -v m
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish 失败，退出码 $LASTEXITCODE"
    }

    $exe = Join-Path $Target 'Stardrop.exe'
    if (-not (Test-Path $exe)) {
        throw "发布完成但没有找到 $exe"
    }

    Write-Done "已发布：$exe"
    return $true
}

try {
    if ($InstallDirectory -and -not $NoBuild) {
        $InstallDirectory = (Resolve-Path -LiteralPath $InstallDirectory).Path
        Assert-StardropClosed $InstallDirectory
    }
    if ([string]::IsNullOrWhiteSpace($Source)) {
        $sourceRoot = Get-LatestUpstream
    }
    else {
        $sourceRoot = (Resolve-Path -LiteralPath $Source).Path
        Write-Step "使用源码目录：$sourceRoot"
    }

    $project = Find-Project $sourceRoot
    Write-Step "项目文件：$($project.FullName)"

    $changed = 0
    if (Add-GlobalFontStyle $project) { $changed++ }
    if (Add-NotesFont $project) { $changed++ }
    if (Add-MoveToGroupFeature $project) { $changed++ }
    if (Add-ThumbnailSizeSetting $project) { $changed++ }
    if (Add-CustomCategories $project) { $changed++ }
    if (Add-MultiSelectAndBatch $project) { $changed++ }
    if (Add-CategoryEnhancements $project) { $changed++ }

    if ($changed -eq 0) {
        Write-Host '源码已经打过全部补丁，本次没有改动。' -ForegroundColor Green
    }

    if ($NoBuild) {
        Write-Host '已跳过编译 (-NoBuild)。' -ForegroundColor Green
        exit 0
    }

    if ([string]::IsNullOrWhiteSpace($Output)) {
        $Output = Join-Path $PSScriptRoot 'dist\Stardrop-win-x64'
        if ($InstallDirectory) {
            $Output += '-update-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
        }
    }

    if (-not (Publish-Stardrop $project $Output)) {
        exit 2
    }

    if ($InstallDirectory) {
        Install-StardropBuild $Output $InstallDirectory
    }

    if (-not $NoZip) {
        $zip = (Resolve-Path $Output).Path.TrimEnd('\') + '.zip'
        Write-Step '打包'
        if (Test-Path $zip) { Remove-Item $zip -Force }
        Compress-Archive -Path (Join-Path $Output '*') -DestinationPath $zip -CompressionLevel Optimal
        Write-Done "压缩包：$zip"
    }

    Write-Host ''
    Write-Host '完成。' -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ''
    Write-Host ("失败：" + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
