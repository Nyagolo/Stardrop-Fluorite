using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Stardrop.Models
{
    /// <summary>
    /// Categories the user defines inside Stardrop, stored apart from the mods folder so assigning a
    /// category never touches the filesystem. Assignments are keyed by mod unique ID, which survives
    /// folder moves and reinstalls. A category name can carry the separator to form a subcategory, which
    /// is how the grid nests them.
    /// </summary>
    public class CustomCategoryStore
    {
        public const char Separator = '\\';

        public List<string> Categories { get; set; } = new List<string>();

        public Dictionary<string, string> Assignments { get; set; } = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        [JsonIgnore]
        public string StorePath { get; set; } = String.Empty;

        public static CustomCategoryStore Load(string path)
        {
            var store = new CustomCategoryStore { StorePath = path };

            try
            {
                if (File.Exists(path))
                {
                    var loaded = JsonSerializer.Deserialize<CustomCategoryStore>(File.ReadAllText(path));
                    if (loaded is not null)
                    {
                        store.Categories = loaded.Categories ?? new List<string>();
                        store.Assignments = loaded.Assignments ?? new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                    }
                }
            }
            catch
            {
                // A broken file must not keep the app from starting; the next save rewrites it.
            }

            return store;
        }

        public void Save()
        {
            if (String.IsNullOrWhiteSpace(StorePath))
            {
                return;
            }

            try
            {
                var directory = Path.GetDirectoryName(StorePath);
                if (String.IsNullOrEmpty(directory) is false)
                {
                    Directory.CreateDirectory(directory);
                }

                File.WriteAllText(StorePath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
            }
            catch
            {
                // Losing a category edit is recoverable; crashing the app over it is not.
            }
        }

        public IEnumerable<string> OrderedCategories
        {
            get { return Categories.OrderBy(category => category, StringComparer.CurrentCultureIgnoreCase); }
        }

        public string Normalize(string name)
        {
            if (String.IsNullOrWhiteSpace(name))
            {
                return String.Empty;
            }

            return String.Join(Separator, name.Split('/', Separator).Select(part => part.Trim()).Where(part => part.Length > 0));
        }

        public bool Create(string name)
        {
            var normalized = Normalize(name);
            if (String.IsNullOrEmpty(normalized))
            {
                return false;
            }

            if (Categories.Any(category => category.Equals(normalized, StringComparison.OrdinalIgnoreCase)))
            {
                return false;
            }

            EnsureParents(normalized);
            Categories.Add(normalized);
            Save();
            return true;
        }

        /// <summary>
        /// Adds any missing ancestors of a nested category, so a category created or renamed to
        /// "地图/zuzu" also lists "地图" in the menu instead of only showing up as a grid group.
        /// </summary>
        private void EnsureParents(string normalized)
        {
            var parts = normalized.Split(Separator);
            for (var index = 1; index < parts.Length; index++)
            {
                var parent = String.Join(Separator.ToString(), parts.Take(index));
                if (Categories.Any(category => category.Equals(parent, StringComparison.OrdinalIgnoreCase)) is false)
                {
                    Categories.Add(parent);
                }
            }
        }

        /// <summary>
        /// Removes a category and every subcategory below it, and clears the assignments that pointed at
        /// any of them, so a deleted category cannot linger in the grid.
        /// </summary>
        public void Delete(string name)
        {
            var normalized = Normalize(name);
            if (String.IsNullOrEmpty(normalized))
            {
                return;
            }

            Categories.RemoveAll(category =>
                category.Equals(normalized, StringComparison.OrdinalIgnoreCase)
                || category.StartsWith(normalized + Separator, StringComparison.OrdinalIgnoreCase));

            var stale = Assignments
                .Where(pair => pair.Value.Equals(normalized, StringComparison.OrdinalIgnoreCase)
                    || pair.Value.StartsWith(normalized + Separator, StringComparison.OrdinalIgnoreCase))
                .Select(pair => pair.Key)
                .ToList();

            foreach (var key in stale)
            {
                Assignments.Remove(key);
            }

            Save();
        }

        /// <summary>
        /// Renames a category and every subcategory below it, carrying their assignments along. Used to
        /// nest an existing category under another one, for example renaming "zuzu" to "地图/zuzu".
        /// Returns false when the new name is empty, already taken, or the old name disappears.
        /// </summary>
        public bool Rename(string oldName, string newName)
        {
            var normalizedOld = Normalize(oldName);
            var normalizedNew = Normalize(newName);
            if (String.IsNullOrEmpty(normalizedOld)
                || String.IsNullOrEmpty(normalizedNew)
                || normalizedOld.Equals(normalizedNew, StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            // Moving a category into itself would build an unreadable path and loop the grid.
            if (normalizedNew.StartsWith(normalizedOld + Separator, StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            var affected = Categories
                .Where(category => category.Equals(normalizedOld, StringComparison.OrdinalIgnoreCase)
                    || category.StartsWith(normalizedOld + Separator, StringComparison.OrdinalIgnoreCase))
                .ToList();
            if (affected.Count == 0)
            {
                return false;
            }

            EnsureParents(normalizedNew);

            var replacements = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var category in affected)
            {
                var replacement = normalizedNew + category.Substring(normalizedOld.Length);
                if (Categories.Any(existing => existing.Equals(replacement, StringComparison.OrdinalIgnoreCase) && affected.Contains(existing) is false))
                {
                    return false;
                }
                replacements[category] = replacement;
            }

            foreach (var pair in replacements)
            {
                Categories.RemoveAll(category => category.Equals(pair.Key, StringComparison.OrdinalIgnoreCase));
                Categories.Add(pair.Value);
            }

            foreach (var uniqueId in Assignments.Keys.ToList())
            {
                if (replacements.TryGetValue(Assignments[uniqueId], out var replacement))
                {
                    Assignments[uniqueId] = replacement;
                }
            }

            Save();
            return true;
        }

        public string Get(string uniqueId)
        {
            return Assignments.TryGetValue(uniqueId, out var category) ? category : String.Empty;
        }

        public void Assign(string uniqueId, string category) => AssignMany(new[] { uniqueId }, category);

        internal void AssignMany(IEnumerable<string> uniqueIds, string category)
        {
            var normalized = Normalize(category);
            foreach (var uniqueId in uniqueIds)
            {
                if (String.IsNullOrEmpty(normalized))
                {
                    Assignments.Remove(uniqueId);
                }
                else
                {
                    Assignments[uniqueId] = normalized;
                }
            }

            Save();
        }
    }
}
