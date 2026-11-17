using Stardrop.Models;
using System;
using System.Collections.Generic;
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
        internal static IEnumerable<string> GetTargets(IEnumerable<Mod> mods, Mod clicked)
        {
            if (String.IsNullOrWhiteSpace(Pathing.defaultModPath))
            {
                return Array.Empty<string>();
            }

            var root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(Pathing.defaultModPath));
            var clickedDirectory = clicked.ModFileInfo.DirectoryName;
            var clickedParent = clickedDirectory is null ? null : Path.GetDirectoryName(clickedDirectory);
            var modDirectories = mods.Where(mod => !mod.IsFromCollection)
                .Select(mod => mod.ModFileInfo.DirectoryName)
                .OfType<string>()
                .Where(dir => Pathing.IsSameOrUnder(dir, root))
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            var targets = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var directory in modDirectories)
            {
                for (var parent = Path.GetDirectoryName(directory);
                    parent is not null && !String.Equals(parent, root, StringComparison.OrdinalIgnoreCase);
                    parent = Path.GetDirectoryName(parent))
                {
                    if (!modDirectories.Contains(parent)
                        && !String.Equals(parent, clickedParent, StringComparison.OrdinalIgnoreCase)
                        && !Pathing.IsSameOrUnder(parent, clickedDirectory))
                    {
                        targets.Add(Path.GetRelativePath(root, parent));
                    }
                }
            }
            return targets;
        }

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

            var segments = targetGroup.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (Path.IsPathRooted(targetGroup) || segments.Any(segment =>
                String.IsNullOrWhiteSpace(segment) || segment is "." or ".."
                || segment.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0))
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
            if (!targetRoot.StartsWith(modsRoot + separator, StringComparison.OrdinalIgnoreCase))
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
            if (Pathing.IsSameOrUnder(targetRoot, moveRoot))
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
                // A linked folder can resolve outside the Mods tree even when its path is under it.
                for (var folder = targetRoot; !String.Equals(folder, modsRoot, StringComparison.OrdinalIgnoreCase);
                    folder = Path.GetDirectoryName(folder)!)
                {
                    if (Directory.Exists(folder) && (File.GetAttributes(folder) & FileAttributes.ReparsePoint) != 0)
                    {
                        error = "the target group is a linked folder";
                        return false;
                    }
                }
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