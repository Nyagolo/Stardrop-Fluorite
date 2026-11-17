using Avalonia;
using Avalonia.Collections;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Markup.Xaml.MarkupExtensions;
using Avalonia.VisualTree;
using Stardrop.Models;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;

namespace Stardrop.Views
{
    internal static class ModGridViewport
    {
        // Avalonia 0.10 exposes collapsing and scrolling to a row, but no public group state or pixel scroll API.
        private const BindingFlags GridInternals = BindingFlags.Instance | BindingFlags.NonPublic;
        private static readonly MethodInfo? GetGroupInfo = typeof(DataGrid).GetMethod("RowGroupInfoFromCollectionViewGroup", GridInternals);
        private static readonly PropertyInfo? IsGroupExpanded = GetGroupInfo?.ReturnType.GetProperty("IsVisible");
        private static readonly MethodInfo? ScrollVertically = typeof(DataGrid).GetMethod("ProcessVerticalScroll", GridInternals);
        private static readonly PropertyInfo? ParentGroup = typeof(DataGridCollectionViewGroup).Assembly
            .GetType("Avalonia.Collections.DataGridCollectionViewGroupInternal")?.GetProperty("Parent", GridInternals);
        // Avalonia 0.10 can corrupt the scrolling row indexes while inserting expanded rows
        // into the recycled viewport. Update its group slots, then lay out a fresh viewport.
        private static readonly MethodInfo ResetDisplayedRows = GridMethod("ResetDisplayedRows");
        private static readonly MethodInfo UpdateDisplayedRows = GridMethod("UpdateDisplayedRows");
        private static readonly MethodInfo UpdateGroupSlots = GridMethod("UpdateRowGroupVisibility");
        private static readonly MethodInfo NextVisibleSlot = GridMethod("GetNextVisibleSlot");
        private static readonly MethodInfo PreviousVisibleSlot = GridMethod("GetPreviousVisibleSlot");
        private static readonly MethodInfo ComputeScrollBars = GridMethod("ComputeScrollBarsLayout");
        private static readonly MethodInfo SetVerticalOffset = GridMethod("SetVerticalOffset");
        private static readonly MethodInfo ItemFromSlot = GridMethod("ItemFromSlot");
        private static readonly PropertyInfo GroupSlot = GetGroupInfo!.ReturnType.GetProperty("Slot")!;
        private static readonly PropertyInfo CurrentSlot = typeof(DataGrid).GetProperty("CurrentSlot", GridInternals)!;
        private static readonly PropertyInfo SlotCount = typeof(DataGrid).GetProperty("SlotCount", GridInternals)!;
        private static readonly PropertyInfo CellsHeight = typeof(DataGrid).GetProperty("CellsHeight", GridInternals)!;
        private static readonly PropertyInfo ClippedRowOffset = typeof(DataGrid).GetProperty("NegVerticalOffset", GridInternals)!;
        private static readonly PropertyInfo DisplayData = typeof(DataGrid).GetProperty("DisplayData", GridInternals)!;
        private static readonly PropertyInfo FirstScrollingSlot = DisplayData.PropertyType.GetProperty("FirstScrollingSlot")!;
        private static readonly FieldInfo ExpanderSubscription =
            typeof(DataGridRowGroupHeader).GetField("_expanderButtonSubscription", GridInternals)!;
        private static readonly ConditionalWeakTable<DataGridRowGroupHeader, DataGrid> HeaderOwners = new();

        private static MethodInfo GridMethod(string name) => typeof(DataGrid).GetMethod(name, GridInternals)!;

        internal static void AttachGroupInput(DataGrid grid)
        {
            grid.AddHandler(InputElement.KeyDownEvent, OnGroupKey, RoutingStrategies.Tunnel);
            grid.AddHandler(InputElement.PointerPressedEvent, OnGroupDoubleClick, RoutingStrategies.Tunnel);
        }

        private static void OnGroupKey(object? sender, KeyEventArgs args)
        {
            if (sender is DataGrid grid && args.Key is Key.Left or Key.Right && args.KeyModifiers == KeyModifiers.None
                && args.Source is not TextBox
                && ItemFromSlot.Invoke(grid, new object[] { CurrentSlot.GetValue(grid)!, 0 }) is DataGridCollectionViewGroup group
                && !ReferenceEquals(group.Key, Mod.DirectCategoryGroup))
            {
                args.Handled = true;
                SetGroupsExpanded(grid, new[] { group }, args.Key == Key.Right);
            }
        }

        private static void OnGroupDoubleClick(object? sender, PointerPressedEventArgs args)
        {
            if (sender is not DataGrid grid || args.ClickCount != 2
                || !args.GetCurrentPoint(grid).Properties.IsLeftButtonPressed || args.Source is not IVisual source)
            {
                return;
            }
            if (source.FindAncestorOfType<ToggleButton>(includeSelf: true) is not null)
            {
                return;
            }
            var header = source.FindAncestorOfType<DataGridRowGroupHeader>(includeSelf: true);
            if (header?.DataContext is DataGridCollectionViewGroup group && GetGroupInfo!.Invoke(grid, new object[] { group }) is object info)
            {
                args.Handled = true;
                SetGroupsExpanded(grid, new[] { group }, !(bool)IsGroupExpanded!.GetValue(info)!);
            }
        }

        internal static void SetGroupsExpanded(DataGrid grid, IEnumerable<DataGridCollectionViewGroup> groups, bool expanded)
        {
            var changes = groups.Where(group => group.ItemCount > 0)
                .Select(group => GetGroupInfo!.Invoke(grid, new object[] { group }))
                .OfType<object>()
                .Where(info => (bool)IsGroupExpanded!.GetValue(info)! != expanded)
                .ToArray();
            if (changes.Length == 0 || !grid.CommitEdit())
            {
                return;
            }

            var first = (int)FirstScrollingSlot.GetValue(DisplayData.GetValue(grid))!;
            var offset = grid.GetVisualDescendants().OfType<ScrollBar>()
                .FirstOrDefault(bar => bar.Name == "PART_VerticalScrollbar")?.Value ?? 0;
            ResetDisplayedRows.Invoke(grid, null);
            foreach (var info in changes)
            {
                var slot = (int)GroupSlot.GetValue(info)!;
                if ((int)NextVisibleSlot.Invoke(grid, new object[] { slot - 1 })! != slot)
                {
                    // A collapsed ancestor controls which of this branch's slots are visible.
                    IsGroupExpanded!.SetValue(info, expanded);
                    continue;
                }
                var heightChange = (double)UpdateGroupSlots.Invoke(grid, new[] { info, expanded, false })!;
                if (slot < first)
                {
                    offset += heightChange;
                }
            }

            var count = (int)SlotCount.GetValue(grid)!;
            if (count > 0)
            {
                var start = (int)NextVisibleSlot.Invoke(grid, new object[] { Math.Max(-1, first - 1) })!;
                if (start >= count)
                {
                    start = (int)PreviousVisibleSlot.Invoke(grid, new object[] { count })!;
                }
                if (start != first || changes.Length > 1)
                {
                    ClippedRowOffset.SetValue(grid, 0d);
                }
                SetVerticalOffset.Invoke(grid, new object[] { start == 0 ? 0d : Math.Max(0, offset) });
                UpdateDisplayedRows.Invoke(grid, new object[] { start, CellsHeight.GetValue(grid)! });
            }

            ComputeScrollBars.Invoke(grid, null);
            grid.InvalidateMeasure();
        }

        internal static void PrepareGroupInput(DataGrid grid, DataGridRowGroupHeader header)
        {
            if (!HeaderOwners.TryGetValue(header, out _))
            {
                HeaderOwners.Add(header, grid);
                header.TemplateApplied += ReplaceExpanderSubscription;
            }
        }

        private static void ReplaceExpanderSubscription(object? sender, TemplateAppliedEventArgs args)
        {
            if (sender is not DataGridRowGroupHeader header || args.NameScope.Find<ToggleButton>("ExpanderButton") is not ToggleButton button)
            {
                return;
            }
            (ExpanderSubscription.GetValue(header) as IDisposable)?.Dispose();
            ExpanderSubscription.SetValue(header, null);
            button.PropertyChanged += (_, change) =>
            {
                if (change.Property == ToggleButton.IsCheckedProperty
                    && header.DataContext is DataGridCollectionViewGroup group
                    && HeaderOwners.TryGetValue(header, out var grid))
                {
                    SetGroupsExpanded(grid, new[] { group }, button.IsChecked == true);
                }
            };
        }

        private const string BoundaryClass = "CategoryBoundary";

        private sealed record RowKey(string UniqueId, string? SourceId, string? Directory, string Category);
        private sealed record Anchor(RowKey? Row, string? Group, double Top);

        internal static void PrepareHeader(DataGridRowGroupHeader header)
        {
            const string directCategoryClass = "DirectCategory";
            var group = header.DataContext as DataGridCollectionViewGroup;
            var isDirectCategory = ReferenceEquals(group?.Key, Mod.DirectCategoryGroup);
            if (isDirectCategory)
            {
                // The grid sets IsVisible itself when it reuses a header. Give these headers zero
                // layout height so they stay out of the list after scrolling and regrouping.
                header.MinHeight = 0;
                header.MaxHeight = 0;
                header.ClipToBounds = true;
                header.IsHitTestVisible = false;
                header.Focusable = false;
            }
            else if (header.Classes.Contains(directCategoryClass))
            {
                header.ClearValue(DataGridRowGroupHeader.MinHeightProperty);
                header.ClearValue(DataGridRowGroupHeader.MaxHeightProperty);
                header.ClearValue(DataGridRowGroupHeader.ClipToBoundsProperty);
                header.ClearValue(DataGridRowGroupHeader.IsHitTestVisibleProperty);
                header.ClearValue(DataGridRowGroupHeader.FocusableProperty);
            }
            header.Classes.Set(directCategoryClass, isDirectCategory);
            var startsSubcategories = !isDirectCategory && group is not null
                && ParentGroup?.GetValue(group) is DataGridCollectionViewGroup parent
                && parent.Items.Count > 1
                && parent.Items[0] is DataGridCollectionViewGroup direct
                && ReferenceEquals(direct.Key, Mod.DirectCategoryGroup) && direct.ItemCount > 0
                && ReferenceEquals(parent.Items[1], group);
            if (startsSubcategories != header.Classes.Contains(BoundaryClass))
            {
                header.Classes.Set(BoundaryClass, startsSubcategories);
                if (startsSubcategories)
                {
                    header.TemplateApplied += CategoryBoundaryTemplateApplied;
                }
                else
                {
                    header.TemplateApplied -= CategoryBoundaryTemplateApplied;
                }
                SetBoundaryLine(header.GetVisualChildren().OfType<Grid>().FirstOrDefault(), startsSubcategories);
            }
        }

        private static void CategoryBoundaryTemplateApplied(object? sender, TemplateAppliedEventArgs args) =>
            SetBoundaryLine(args.NameScope.Find<Grid>("PART_Root"), true);

        private static void SetBoundaryLine(Grid? root, bool visible)
        {
            if (root is null)
            {
                return;
            }
            var line = root.Children.OfType<Border>().FirstOrDefault(child => child.Name == "CategoryBoundaryLine");
            if (line is null && visible)
            {
                line = new Border
                {
                    Name = "CategoryBoundaryLine",
                    Height = 2,
                    VerticalAlignment = VerticalAlignment.Top,
                    IsHitTestVisible = false,
                    ZIndex = 1
                };
                line.Bind(Border.BackgroundProperty, new DynamicResourceExtension("HighlightBrush"));
                Grid.SetColumnSpan(line, root.ColumnDefinitions.Count);
                root.Children.Add(line);
            }
            if (line is not null)
            {
                line.IsVisible = visible;
            }
        }

        internal static IEnumerable<(string Path, DataGridCollectionViewGroup Group)> RealGroups(
            IEnumerable<object>? items, string prefix = "")
        {
            if (items is null)
            {
                yield break;
            }
            foreach (var group in items.OfType<DataGridCollectionViewGroup>())
            {
                if (ReferenceEquals(group.Key, Mod.DirectCategoryGroup))
                {
                    continue;
                }
                var path = prefix + Convert.ToString(group.Key);
                yield return (path, group);
                foreach (var child in RealGroups(group.Items, path + CustomCategoryStore.Separator))
                {
                    yield return child;
                }
            }
        }

        internal static void Preserve(DataGrid grid, DataGridCollectionView view, Action update, Func<string, string>? rename = null)
        {
            rename ??= path => path;
            var grouping = view.GroupDescriptions.FirstOrDefault()?.PropertyName;
            var groups = RealGroups(view.Groups).ToDictionary(pair => pair.Group, pair => rename(pair.Path));
            var collapsed = groups.Where(pair => GetGroupInfo?.Invoke(grid, new object[] { pair.Key }) is object info
                    && IsGroupExpanded?.GetValue(info) is false)
                .Select(pair => pair.Value)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            var scrollBar = grid.GetVisualDescendants().OfType<ScrollBar>()
                .FirstOrDefault(bar => bar.Name == "PART_VerticalScrollbar");
            var offset = scrollBar?.Value ?? 0;
            var presenter = grid.GetVisualDescendants().OfType<DataGridRowsPresenter>().FirstOrDefault();
            var anchors = presenter?.GetVisualChildren().OfType<Control>()
                .Where(row => row.IsVisible && row.Bounds.Height > 0 && row.Bounds.Bottom > 0 && row.Bounds.Top < presenter.Bounds.Height)
                .OrderBy(row => row.Bounds.Top)
                .Select(row => row.DataContext switch
                {
                    Mod mod => new Anchor(KeyFor(mod, rename), null, row.Bounds.Top),
                    DataGridCollectionViewGroup group when groups.TryGetValue(group, out var path) => new Anchor(null, path, row.Bounds.Top),
                    _ => null
                })
                .OfType<Anchor>()
                .ToList();

            update();

            if (grid.GetVisualRoot() is not ILayoutRoot root)
            {
                return;
            }
            var sameGrouping = grouping == view.GroupDescriptions.FirstOrDefault()?.PropertyName;
            var currentGroups = new Dictionary<string, DataGridCollectionViewGroup>(StringComparer.OrdinalIgnoreCase);
            if (sameGrouping)
            {
                // Descendants first, so restoring their state never reopens a collapsed ancestor.
                var restoreCollapsed = new List<DataGridCollectionViewGroup>();
                foreach (var (path, group) in RealGroups(view.Groups).Reverse())
                {
                    currentGroups.TryAdd(path, group);
                    if (collapsed.Contains(path))
                    {
                        restoreCollapsed.Add(group);
                    }
                }
                SetGroupsExpanded(grid, restoreCollapsed, expanded: false);
            }

            root.LayoutManager.ExecuteLayoutPass();
            presenter = grid.GetVisualDescendants().OfType<DataGridRowsPresenter>().FirstOrDefault();
            scrollBar = grid.GetVisualDescendants().OfType<ScrollBar>()
                .FirstOrDefault(bar => bar.Name == "PART_VerticalScrollbar");
            var rows = view.OfType<Mod>().ToLookup(mod => KeyFor(mod, path => path));
            // Try surviving rows before headers. A heading high above the surviving rows may
            // now be at the end of a shrunken group and cannot preserve the same reading position.
            foreach (var anchor in (anchors ?? Enumerable.Empty<Anchor>()).OrderBy(anchor => anchor.Row is null))
            {
                object? item = anchor.Row is RowKey row ? rows[row].FirstOrDefault()
                    : anchor.Group is string path && currentGroups.TryGetValue(path, out var group) ? group : null;
                if (item is null)
                {
                    continue;
                }

                var element = FindDisplayedItem(presenter, item);
                if (element is null)
                {
                    grid.ScrollIntoView(item, null);
                    root.LayoutManager.ExecuteLayoutPass();
                    element = FindDisplayedItem(presenter, item);
                }
                if (element is null)
                {
                    continue;
                }
                if (scrollBar is not null)
                {
                    SetOffset(grid, scrollBar, scrollBar.Value + element.Bounds.Top - anchor.Top);
                    root.LayoutManager.ExecuteLayoutPass();
                }
                return;
            }
            if (scrollBar is not null)
            {
                SetOffset(grid, scrollBar, offset);
                root.LayoutManager.ExecuteLayoutPass();
            }
        }

        private static Control? FindDisplayedItem(DataGridRowsPresenter? presenter, object item) =>
            presenter?.GetVisualChildren().OfType<Control>()
                .FirstOrDefault(control => control.IsVisible && control.Bounds.Height > 0
                    && ReferenceEquals(control.DataContext, item));

        private static RowKey KeyFor(Mod mod, Func<string, string> rename) =>
            new RowKey(mod.UniqueId, mod.SourceId, mod.ModFileInfo.DirectoryName, rename(mod.CustomCategory));

        private static void SetOffset(DataGrid grid, ScrollBar scrollBar, double offset)
        {
            if (ScrollVertically is not null)
            {
                scrollBar.Value = Math.Clamp(offset, scrollBar.Minimum, scrollBar.Maximum);
                ScrollVertically.Invoke(grid, new object[] { ScrollEventType.ThumbTrack });
            }
        }
    }
}
