using Stardrop.Utilities;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace Stardrop.Models
{
    internal static class SharedModNotes
    {
        private static Dictionary<string, string> _notes = new(StringComparer.OrdinalIgnoreCase);
        private static string FilePath => Path.Combine(Pathing.defaultHomePath, "SharedModNotes.json");

        internal static void Initialize(IEnumerable<Profile> profiles)
        {
            if (File.Exists(FilePath))
            {
                var notes = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(FilePath))
                    ?? throw new JsonException("Shared mod notes must be a JSON object.");
                _notes = new Dictionary<string, string>(notes, StringComparer.OrdinalIgnoreCase);
                return;
            }

            var migrated = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var entries = profiles.SelectMany(profile => profile.Notes ?? new List<ModNote>())
                .Where(note => !String.IsNullOrWhiteSpace(note?.UniqueId) && !String.IsNullOrWhiteSpace(note.Note));
            foreach (var group in entries.GroupBy(note => note.UniqueId, StringComparer.OrdinalIgnoreCase))
            {
                var distinct = group.Select(note => note.Note.ReplaceLineEndings("\n").Trim())
                    .Distinct(StringComparer.Ordinal).ToArray();
                var complete = distinct.Where(note => !distinct.Any(other =>
                    other.Length > note.Length && other.StartsWith(note, StringComparison.Ordinal)));
                migrated.Add(group.Key, String.Join("\n\n", complete));
            }
            Write(migrated);
        }

        internal static string Get(string uniqueId) => _notes.GetValueOrDefault(uniqueId) ?? String.Empty;

        internal static List<ModNote> Export() => _notes.Where(pair => !String.IsNullOrEmpty(pair.Value))
            .Select(pair => new ModNote(pair.Key, pair.Value)).ToList();

        internal static void Set(string uniqueId, string note)
        {
            // Preserve an explicit clear so an older profile import cannot resurrect it.
            var updated = new Dictionary<string, string>(_notes, StringComparer.OrdinalIgnoreCase) { [uniqueId] = note };
            Write(updated);
        }

        internal static void Import(IEnumerable<ModNote> notes)
        {
            var updated = new Dictionary<string, string>(_notes, StringComparer.OrdinalIgnoreCase);
            foreach (var note in notes)
            {
                if (!String.IsNullOrWhiteSpace(note?.UniqueId) && !String.IsNullOrWhiteSpace(note.Note))
                {
                    updated.TryAdd(note.UniqueId, note.Note.ReplaceLineEndings("\n"));
                }
            }
            if (updated.Count != _notes.Count)
            {
                Write(updated);
            }
        }

        private static void Write(Dictionary<string, string> notes)
        {
            var target = FilePath;
            var temporary = target + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                File.WriteAllText(temporary, JsonSerializer.Serialize(notes, new JsonSerializerOptions { WriteIndented = true }));
                File.Move(temporary, target, overwrite: true);
                _notes = notes;
            }
            finally
            {
                File.Delete(temporary);
            }
        }
    }
}
