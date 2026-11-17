using Avalonia.Collections;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Input;
using Avalonia.Controls.Primitives;
using Avalonia.VisualTree;
using Avalonia.Markup.Xaml;
using Stardrop.Models;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Stardrop.Views
{
    public partial class BatchCategoryWindow : Window
    {
        private readonly Dictionary<string, TreeViewItem> _nodes = new(StringComparer.OrdinalIgnoreCase);
        private readonly IReadOnlyList<Mod> _mods = Array.Empty<Mod>();
        private readonly Func<Window, Task<string?>>? _create;
        private readonly Func<string, Window, Task<string?>>? _rename;
        private readonly Func<string, Window, Task<bool>>? _delete;
        private readonly int _selectionCount;
        private TreeView Tree => this.FindControl<TreeView>("categoryTree");
        private TreeViewItem? SelectedNode => Tree.SelectedItem as TreeViewItem;

        public BatchCategoryWindow()
        {
            AvaloniaXamlLoader.Load(this);
            Tree.AddHandler(InputElement.PointerPressedEvent, CategoryTree_PointerPressed, RoutingStrategies.Tunnel);
            UpdateButtons();
        }

        internal BatchCategoryWindow(int selectionCount, IReadOnlyList<Mod> mods,
            Func<Window, Task<string?>> create, Func<string, Window, Task<string?>> rename,
            Func<string, Window, Task<bool>> delete) : this()
        {
            _mods = mods;
            _selectionCount = selectionCount;
            _create = create;
            _rename = rename;
            _delete = delete;
            this.FindControl<StackPanel>("batchOptions").IsVisible = selectionCount > 0;
            this.FindControl<Button>("applyButton").IsVisible = selectionCount > 0;
            this.FindControl<TextBlock>("summaryText").Text =
                String.Format(Program.translation.Get("ui.batch_category.summary"), selectionCount);
            RefreshTree();
        }

        public string SelectedCategory => SelectedNode?.Tag as string ?? String.Empty;
        public bool IncludeSiblings => this.FindControl<CheckBox>("includeSiblingsBox").IsChecked == true;

        private void RefreshTree(string? selection = null, string? renamedFrom = null)
        {
            var expanded = _nodes.Where(pair => pair.Value.IsExpanded).Select(pair => pair.Key)
                .Select(path => renamedFrom is not null && selection is not null
                    && (path.Equals(renamedFrom, StringComparison.OrdinalIgnoreCase)
                        || path.StartsWith(renamedFrom + CustomCategoryStore.Separator, StringComparison.OrdinalIgnoreCase))
                    ? selection + path.Substring(renamedFrom.Length) : path)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);

            var store = Program.customCategories;
            var counts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            foreach (var mod in _mods)
            {
                var path = store.Get(mod.UniqueId);
                while (true)
                {
                    counts[path] = counts.GetValueOrDefault(path) + 1;
                    var separator = path.LastIndexOf(CustomCategoryStore.Separator);
                    if (separator < 0)
                    {
                        break;
                    }
                    path = path[..separator];
                }
            }

            _nodes.Clear();
            var roots = new AvaloniaList<TreeViewItem>
            {
                CreateNode(String.Empty, Program.translation.Get("ui.main_window.menu_items.context.custom_category_none"))
            };
            foreach (var path in store.OrderedCategories.Concat(counts.Keys).Distinct(StringComparer.OrdinalIgnoreCase)
                .Where(path => path.Length > 0))
            {
                AddPath(path);
            }

            Tree.Items = roots;
            if (_nodes.TryGetValue(selection ?? String.Empty, out var target))
            {
                var path = selection ?? String.Empty;
                for (var separator = path.LastIndexOf(CustomCategoryStore.Separator); separator >= 0;
                    separator = path.LastIndexOf(CustomCategoryStore.Separator))
                {
                    path = path[..separator];
                    _nodes[path].IsExpanded = true;
                }
                Tree.SelectedItem = target;
            }
            UpdateButtons();

            TreeViewItem CreateNode(string path, string name)
            {
                var node = new TreeViewItem
                {
                    Header = $"{name} ({counts.GetValueOrDefault(path)})",
                    Tag = path,
                    Items = new AvaloniaList<TreeViewItem>(),
                    IsExpanded = expanded.Contains(path)
                };
                _nodes.Add(path, node);
                return node;
            }

            TreeViewItem AddPath(string path)
            {
                if (_nodes.TryGetValue(path, out var existing))
                {
                    return existing;
                }
                var separator = path.LastIndexOf(CustomCategoryStore.Separator);
                var parent = separator < 0 ? roots : (AvaloniaList<TreeViewItem>)AddPath(path[..separator]).Items;
                var node = CreateNode(path, path[(separator + 1)..]);
                parent.Add(node);
                return node;
            }
        }

        private void CategoryTree_PointerPressed(object? sender, PointerPressedEventArgs e)
        {
            if (e.Source is not IVisual source
                || !e.GetCurrentPoint(Tree).Properties.IsLeftButtonPressed
                || source.FindAncestorOfType<ToggleButton>(includeSelf: true) is not null
                || source.FindAncestorOfType<TreeViewItem>(includeSelf: true) is not TreeViewItem node
                || !node.Items.OfType<TreeViewItem>().Any())
            {
                return;
            }

            Tree.SelectedItem = node;
            node.IsExpanded = !node.IsExpanded;
            e.Handled = true;
        }

        private void CategoryTree_SelectionChanged(object? sender, SelectionChangedEventArgs e) => UpdateButtons();

        private void UpdateButtons()
        {
            bool hasNamedCategory = SelectedCategory.Length > 0;
            this.FindControl<Button>("renameButton").IsEnabled = hasNamedCategory;
            this.FindControl<Button>("deleteButton").IsEnabled = hasNamedCategory;
            this.FindControl<Button>("applyButton").IsEnabled = _selectionCount > 0 && SelectedNode is not null;
        }

        private async void Create_Click(object? sender, RoutedEventArgs e)
        {
            if (_create is not null && await _create(this) is string path)
            {
                RefreshTree(path);
            }
        }

        private async void Rename_Click(object? sender, RoutedEventArgs e)
        {
            var selected = SelectedCategory;
            if (_rename is not null && selected.Length > 0 && await _rename(selected, this) is string renamed)
            {
                RefreshTree(renamed, selected);
            }
        }

        private async void Delete_Click(object? sender, RoutedEventArgs e)
        {
            var selected = SelectedCategory;
            if (_delete is not null && selected.Length > 0 && await _delete(selected, this))
            {
                var separator = selected.LastIndexOf(CustomCategoryStore.Separator);
                RefreshTree(separator < 0 ? null : selected[..separator]);
            }
        }

        private void Apply_Click(object? sender, RoutedEventArgs e) => Close(true);

        private void Close_Click(object? sender, RoutedEventArgs e) => Close(false);
    }
}
