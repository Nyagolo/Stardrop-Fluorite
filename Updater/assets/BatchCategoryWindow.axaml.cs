using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Markup.Xaml;
using System;
using System.Collections.Generic;
using System.Linq;

namespace Stardrop.Views
{
    /// <summary>
    /// Assigns one custom category to a batch of selected mods, optionally taking every mod in the same
    /// folder along. Categories are a view-level concept, so this never touches the mods folder.
    /// </summary>
    public partial class BatchCategoryWindow : Window
    {
        private readonly List<string> _categories = new List<string>();

        public BatchCategoryWindow()
        {
            InitializeComponent();
        }

        public BatchCategoryWindow(int modCount, IEnumerable<string> categories) : this()
        {
            _categories.Add(String.Empty);
            _categories.AddRange(categories);

            var categoryList = this.FindControl<ListBox>("categoryList");
            var uncategorized = Program.translation.Get("ui.main_window.menu_items.context.custom_category_none");
            categoryList.Items = _categories
                .Select(category => String.IsNullOrEmpty(category) ? uncategorized : category)
                .ToList();
            categoryList.SelectedIndex = 0;

            this.FindControl<TextBlock>("summaryText").Text = String.Format(Program.translation.Get("ui.batch_category.summary"), modCount);
            this.FindControl<CheckBox>("includeSiblingsBox").IsChecked = false;

            this.FindControl<Button>("applyButton").Click += ApplyButton_Click;
            this.FindControl<Button>("cancelButton").Click += delegate { this.Close(false); };
        }

        public string SelectedCategory
        {
            get
            {
                var index = this.FindControl<ListBox>("categoryList").SelectedIndex;
                return index >= 0 && index < _categories.Count ? _categories[index] : String.Empty;
            }
        }

        public bool IncludeSiblings
        {
            get { return this.FindControl<CheckBox>("includeSiblingsBox").IsChecked == true; }
        }

        private void ApplyButton_Click(object? sender, RoutedEventArgs e)
        {
            this.Close(true);
        }

        private void InitializeComponent()
        {
            AvaloniaXamlLoader.Load(this);
        }
    }
}
