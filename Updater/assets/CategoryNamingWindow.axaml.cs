using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Markup.Xaml;
using System;

namespace Stardrop.Views
{
    /// <summary>
    /// Asks for a custom category name. The returned string is the raw text; the caller normalizes it,
    /// since '/' and '\' both mean "subcategory" and the store owns that rule.
    /// </summary>
    public partial class CategoryNamingWindow : Window
    {
        public CategoryNamingWindow()
        {
            InitializeComponent();

            var nameBox = this.FindControl<TextBox>("categoryNameBox");
            this.FindControl<Button>("applyButton").Click += ApplyButton_Click;
            this.FindControl<Button>("cancelButton").Click += delegate { this.Close(null); };

            nameBox.AttachedToVisualTree += (sender, args) => nameBox.Focus();
            nameBox.KeyDown += NameBox_KeyDown;
        }

        /// <summary>
        /// Opens the dialog prefilled, used for renaming a category to a nested path such as
        /// "地图/zuzu" so an existing category can be moved under another one.
        /// </summary>
        public CategoryNamingWindow(string? initialText, bool isRename) : this()
        {
            if (isRename)
            {
                this.Title = Stardrop.Program.translation.Get("ui.category_window.rename_title");
            }

            var nameBox = this.FindControl<TextBox>("categoryNameBox");
            nameBox.Text = initialText ?? String.Empty;
            nameBox.CaretIndex = nameBox.Text?.Length ?? 0;
        }

        private void ApplyButton_Click(object? sender, RoutedEventArgs e)
        {
            this.Close(this.FindControl<TextBox>("categoryNameBox").Text);
        }

        private void NameBox_KeyDown(object? sender, KeyEventArgs e)
        {
            if (e.Key == Key.Enter)
            {
                this.Close(this.FindControl<TextBox>("categoryNameBox").Text);
            }
        }

        private void InitializeComponent()
        {
            AvaloniaXamlLoader.Load(this);
        }
    }
}
