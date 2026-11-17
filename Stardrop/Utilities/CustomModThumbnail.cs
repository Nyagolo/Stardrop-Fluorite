using Avalonia.Media.Imaging;
using SkiaSharp;
using Stardrop.Models.Data;
using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace Stardrop.Utilities
{
    internal static class CustomModThumbnail
    {
        private const int ThumbnailSize = 256;

        internal static string GetPath(ModReference mod)
        {
            var identity = $"{mod.UniqueId.ToUpperInvariant()}\0{mod.SourceId?.ToUpperInvariant()}";
            var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(identity)));
            return Path.Combine(Path.GetDirectoryName(Pathing.GetThumbnailsPath())!, "Custom", key + ".png");
        }

        internal static void Save(ModReference mod, string imagePath)
        {
            using var stream = File.OpenRead(imagePath);
            SKImageInfo dimensions;
            using (var codec = SKCodec.Create(new SKManagedStream(stream, false)))
            {
                if (codec is null)
                {
                    throw new InvalidDataException("The selected file is not a readable image.");
                }
                dimensions = codec.Info;
            }
            if ((long)dimensions.Width * dimensions.Height > 50_000_000)
            {
                throw new InvalidDataException("The selected image has too many pixels.");
            }
            stream.Position = 0;
            using var thumbnail = Math.Max(dimensions.Width, dimensions.Height) <= ThumbnailSize
                ? new Bitmap(stream)
                : dimensions.Width >= dimensions.Height
                    ? Bitmap.DecodeToWidth(stream, ThumbnailSize)
                    : Bitmap.DecodeToHeight(stream, ThumbnailSize);

            var destination = GetPath(mod);
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            var temporary = destination + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                using (var output = File.Open(temporary, FileMode.CreateNew, FileAccess.Write))
                {
                    thumbnail.Save(output);
                }
                File.Move(temporary, destination, overwrite: true);
            }
            finally
            {
                File.Delete(temporary);
            }
        }
    }
}
