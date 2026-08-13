"""
OS Info & Commands Viewer
Multi-platform tool to view and edit OS information and command outputs.

Usage:
    python os_info.py              # Launch GUI (default)
    python os_info.py --cli        # Launch CLI (terminal mode)
    python os_info.py --gui        # Launch GUI (explicit)
    python os_info.py -h           # Show help
"""

import os
import json
import getpass
import sys
import subprocess
import argparse
import shlex

# Base path
BASE_ROOT = os.path.expanduser("~")
OS_INFO_BASE = os.path.join(BASE_ROOT, "os_info")


def check_user():
    """Ensure script runs as vmuser, re-executing via su if needed."""
    if getpass.getuser() == "vmuser":
        return

    script_path = os.path.abspath(__file__)
    # Build command preserving display-related environment variables so GUI works
    base_args = [sys.executable, script_path] + sys.argv[1:]

    env_prefix = []
    for var in ("DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY"):
        val = os.environ.get(var)
        if val:
            env_prefix.append(f"{var}={shlex.quote(val)}")

    cmd_parts = env_prefix + [shlex.quote(a) for a in base_args]
    cmd_str = " ".join(cmd_parts)

    su_cmd = ["su", "-", "vmuser", "-c", cmd_str]

    print("Re-running script as user 'vmuser'...")
    try:
        os.execvp("su", su_cmd)
    except OSError as exc:
        print(f"Error switching to 'vmuser' using su: {exc}")
        print("Please run: su - vmuser and launch the script again.")
        sys.exit(1)


def run_gui(explicit=False):
    """Launch GUI mode.

    If explicit is True (user passed --gui), any failure is reported and the
    script exits instead of falling back. Otherwise (default invocation with
    no options) a failure falls back to CLI mode.
    """
    # Try to load tkinter
    try:
        import tkinter as tk
        from tkinter import ttk, messagebox
    except ImportError:
        print("Error: tkinter is not installed. Install it with: apt install python3-tk")
        if explicit:
            sys.exit(1)
        run_cli()
        return

    # If there is no DISPLAY/WAYLAND_DISPLAY, try to configure a reasonable default
    if os.name == "posix" and not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
        # Typical case: when using 'su - vmuser' DISPLAY is lost; try :0
        os.environ.setdefault("DISPLAY", ":0")

    from gui_mode import OSInfoGUI

    try:
        app = OSInfoGUI()
        app.mainloop()
    except tk.TclError as exc:
        print(f"Error launching GUI: {exc}")
        if explicit:
            sys.exit(1)
        print("Falling back to CLI mode...")
        run_cli()


def run_cli():
    """Launch CLI mode."""
    from cli_mode import main_menu
    main_menu()


def main():
    """Main entry point with argument parsing."""
    parser = argparse.ArgumentParser(
        description="OS Info & Commands Viewer - View and edit VM information",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s              # Launch GUI (default)
  %(prog)s --cli        # Launch CLI (terminal)
  %(prog)s --gui        # Launch GUI (explicit)
        """
    )
    
    # Mode argument
    mode_group = parser.add_mutually_exclusive_group()
    mode_group.add_argument('--gui', action='store_true', help='Launch GUI mode (default)')
    mode_group.add_argument('--cli', action='store_true', help='Launch CLI mode (terminal)')
    
    args = parser.parse_args()
    
    # Check user
    check_user()
    
    # Determine mode: explicit --cli/--gui, or default to GUI with CLI fallback
    if args.cli:
        run_cli()
    elif args.gui:
        run_gui(explicit=True)
    else:
        run_gui(explicit=False)


if __name__ == "__main__":
    main()
