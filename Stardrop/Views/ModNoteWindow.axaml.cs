using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Interactivity;
using Avalonia.Markup.Xaml;
using Avalonia.Media;
using Avalonia.Threading;
using System;

namespace Stardrop.Views
{
    public partial class ModNoteWindow : Window
    {
        private NativeNoteEditor? _nativeEditor;
        private TextBox? _textBox;

        public ModNoteWindow()
        {
            AvaloniaXamlLoader.Load(this);
        }

        internal ModNoteWindow(string modName, string text) : this()
        {
            this.FindControl<TextBlock>("modName").Text = modName;
            var host = this.FindControl<ContentControl>("editorHost");

            if (OperatingSystem.IsWindows())
            {
                _nativeEditor = new NativeNoteEditor(text);
                host.Content = _nativeEditor;
                Opened += (_, _) => Dispatcher.UIThread.Post(_nativeEditor.FocusEditor, DispatcherPriority.Input);
            }
            else
            {
                _textBox = new TextBox
                {
                    Text = text,
                    AcceptsReturn = true,
                    TextWrapping = TextWrapping.Wrap,
                    Padding = new Avalonia.Thickness(8),
                    FontSize = 16,
                    VerticalContentAlignment = Avalonia.Layout.VerticalAlignment.Top
                };
                ScrollViewer.SetVerticalScrollBarVisibility(_textBox, ScrollBarVisibility.Auto);
                host.Content = _textBox;
                Opened += (_, _) => _textBox.Focus();
            }
        }

        private void Cancel_Click(object? sender, RoutedEventArgs e) => Close(null);

        private void Save_Click(object? sender, RoutedEventArgs e) =>
            Close(_nativeEditor?.Text ?? _textBox?.Text ?? String.Empty);
    }
}
