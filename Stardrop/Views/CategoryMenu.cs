using Avalonia.Controls;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Stardrop.Views
{
    internal static class CategoryMenu
    {
        private sealed class Node
        {
            public string? Path { get; set; }
            public Dictionary<string, Node> Children { get; } = new(StringComparer.OrdinalIgnoreCase);
        }

        internal static List<MenuItem> Build(IEnumerable<string> paths, char separator, Func<string, Task> select, string emptyLabel)
        {
            var root = new Node();
            foreach (var path in paths)
            {
                var node = root;
                foreach (var name in path.Split(separator, StringSplitOptions.RemoveEmptyEntries))
                {
                    if (!node.Children.TryGetValue(name, out var child))
                    {
                        child = new Node();
                        node.Children.Add(name, child);
                    }
                    node = child;
                }
                node.Path ??= path;
            }

            if (root.Children.Count == 0)
            {
                return new List<MenuItem> { new MenuItem { Header = emptyLabel, IsEnabled = false } };
            }
            return BuildChildren(root, select);
        }

        private static List<MenuItem> BuildChildren(Node parent, Func<string, Task> select)
        {
            var items = new List<MenuItem>();
            foreach (var (name, node) in parent.Children.OrderBy(pair => pair.Key, StringComparer.CurrentCultureIgnoreCase))
            {
                if (node.Children.Count == 0 && node.Path is string leaf)
                {
                    items.Add(ActionItem(name, leaf, select));
                    continue;
                }

                var children = BuildChildren(node, select);
                if (node.Path is string path)
                {
                    var label = Program.translation.Get("ui.main_window.menu_items.context.category_choose_parent");
                    children.Insert(0, ActionItem(String.Format(label, name), path, select));
                }
                items.Add(new MenuItem { Header = name, Items = children });
            }
            return items;
        }

        private static MenuItem ActionItem(string header, string path, Func<string, Task> select)
        {
            var item = new MenuItem { Header = header, Tag = path };
            item.Click += async (_, _) => await select(path);
            return item;
        }
    }
}
