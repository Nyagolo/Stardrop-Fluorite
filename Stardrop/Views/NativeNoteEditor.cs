using Avalonia.Controls;
using Avalonia.Platform;
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace Stardrop.Views
{
    // A standard Windows edit control gives the system IME a native text target.
    internal sealed class NativeNoteEditor : NativeControlHost
    {
        private const int Child = 0x40000000, TabStop = 0x00010000, VerticalScroll = 0x00200000;
        private const int Multiline = 0x0004, AutoVerticalScroll = 0x0040, NoHideSelection = 0x0100, WantReturn = 0x1000;
        private const int SetFont = 0x0030, SetSelection = 0x00B1, LimitText = 0x00C5, SetMargins = 0x00D3;
        private const int ScrollCaret = 0x00B7;
        private readonly string _initialText;
        private IntPtr _editor;
        private IntPtr _font;

        internal NativeNoteEditor(string text)
        {
            _initialText = text.ReplaceLineEndings("\r\n");
        }

        internal string Text
        {
            get
            {
                if (_editor == IntPtr.Zero)
                {
                    return _initialText;
                }

                var text = new StringBuilder(GetWindowTextLength(_editor) + 1);
                GetWindowText(_editor, text, text.Capacity);
                return text.ToString();
            }
        }

        internal void FocusEditor()
        {
            if (_editor != IntPtr.Zero)
            {
                SetFocus(_editor);
            }
        }

        protected override IPlatformHandle CreateNativeControlCore(IPlatformHandle parent)
        {
            _editor = CreateWindowEx(0, "EDIT", String.Empty,
                Child | TabStop | VerticalScroll | Multiline | AutoVerticalScroll | NoHideSelection | WantReturn,
                0, 0, 0, 0, parent.Handle, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            if (_editor == IntPtr.Zero)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }

            var dpi = Math.Max(GetDpiForWindow(_editor), 96u);
            _font = CreateFont(-(int)Math.Round(16 * dpi / 96.0), 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 0, 0, "Microsoft YaHei");
            if (_font != IntPtr.Zero)
            {
                SendMessage(_editor, SetFont, _font, new IntPtr(1));
            }

            SendMessage(_editor, LimitText, new IntPtr(Int32.MaxValue - 1), IntPtr.Zero);
            var padding = (int)Math.Round(8 * dpi / 96.0);
            SendMessage(_editor, SetMargins, new IntPtr(3), new IntPtr(padding | (padding << 16)));
            SetWindowText(_editor, _initialText);
            SendMessage(_editor, SetSelection, IntPtr.Zero, IntPtr.Zero);
            SendMessage(_editor, ScrollCaret, IntPtr.Zero, IntPtr.Zero);
            return new PlatformHandle(_editor, "HWND");
        }

        protected override void DestroyNativeControlCore(IPlatformHandle control)
        {
            DestroyWindow(control.Handle);
            if (_font != IntPtr.Zero)
            {
                DeleteObject(_font);
                _font = IntPtr.Zero;
            }
            _editor = IntPtr.Zero;
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateWindowEx(int extendedStyle, string className, string text, int style,
            int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);

        [DllImport("user32.dll")]
        private static extern bool DestroyWindow(IntPtr window);

        [DllImport("user32.dll")]
        private static extern uint GetDpiForWindow(IntPtr window);

        [DllImport("user32.dll")]
        private static extern IntPtr SetFocus(IntPtr window);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowTextLength(IntPtr window);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowText(IntPtr window, StringBuilder value, int size);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern bool SetWindowText(IntPtr window, string value);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr SendMessage(IntPtr window, int message, IntPtr wParam, IntPtr lParam);

        [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr CreateFont(int height, int width, int escapement, int orientation, int weight,
            uint italic, uint underline, uint strikeout, uint charset, uint outputPrecision,
            uint clipPrecision, uint quality, uint pitchAndFamily, string face);

        [DllImport("gdi32.dll")]
        private static extern bool DeleteObject(IntPtr handle);
    }
}
