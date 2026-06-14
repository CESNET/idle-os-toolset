"""GUI mode implementation for OS Info & Commands Viewer."""

import os
import json
import shutil
import subprocess
import shlex
import tkinter as tk
from tkinter import ttk, messagebox

# Base paths
BASE_ROOT = os.path.expanduser("~")
OS_INFO_BASE = os.path.join(BASE_ROOT, "os_info")
VM_INFO_BASE = os.path.join(BASE_ROOT, "vm_info")
TRAFFIC_BASE = os.path.join(BASE_ROOT, "traffic")


class OSInfoGUI(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("OS Info & Commands Viewer")
        self.geometry("1400x850")
        self.resizable(True, True)
        self.configure(bg='#ecf0f1')

        # Custom colors
        self.bg_primary = '#2c3e50'      # Dark blue
        self.bg_secondary = '#34495e'   # Blue gray
        self.bg_accent = '#3498db'      # Bright blue
        self.bg_success = '#27ae60'     # Green
        self.bg_info = '#2980b9'        # Info blue
        self.text_light = '#ecf0f1'     # Light text
        self.text_dark = '#2c3e50'      # Dark text

        # Configure improved styles
        self.style = ttk.Style()
        self.style.theme_use('clam')
        
        # Custom style for LabelFrames
        self.style.configure('Header.TLabel', font=('Helvetica', 12, 'bold'), foreground=self.bg_primary)
        self.style.configure('Subheader.TLabel', font=('Helvetica', 10, 'bold'), foreground=self.bg_primary)
        self.style.configure('Title.TLabel', font=('Helvetica', 14, 'bold'), foreground=self.bg_primary)
        self.style.configure('TLabelframe', background='#ecf0f1', relief='flat', borderwidth=2)
        self.style.configure('TLabelframe.Label', background='#ecf0f1', font=('Helvetica', 11, 'bold'), foreground=self.bg_primary)
        self.style.configure('TButton', font=('Helvetica', 10))
        self.style.map('TButton',
                       background=[('active', self.bg_info)],
                       foreground=[('active', self.text_light)])
        self.style.configure('Save.TButton', font=('Helvetica', 10, 'bold'))
        
        # Custom text entry
        self.style.configure('TEntry', font=('Helvetica', 10), padding=5)

        self.vm_names = self._load_vm_names()
        self.current_index = 0 if self.vm_names else None

        self._build_ui()

        if self.vm_names:
            self._select_vm(0)
        else:
            messagebox.showinfo(
                "No Data Found",
                f"No os_info directories found at: {OS_INFO_BASE}",
            )

    def _load_vm_names(self):
        if not os.path.isdir(OS_INFO_BASE):
            return []
        names = []
        for entry in os.listdir(OS_INFO_BASE):
            full = os.path.join(OS_INFO_BASE, entry)
            if os.path.isdir(full):
                # Consider it a VM if it has at least os_info.json or commands_execute.json
                if (
                    os.path.isfile(os.path.join(full, "os_info.json"))
                    or os.path.isfile(os.path.join(full, "commands_execute.json"))
                ):
                    names.append(entry)
        names.sort()
        return names

    def _build_ui(self):
        # Main frame with padding
        main_frame = ttk.Frame(self, padding=12)
        main_frame.pack(fill=tk.BOTH, expand=True)
        main_frame.columnconfigure(1, weight=1)
        main_frame.rowconfigure(1, weight=1)

        # ===== LEFT PANEL: Machine list =====
        left_frame = ttk.LabelFrame(
            main_frame,
            text="💻  Virtual Machines",
            padding=10
        )
        left_frame.grid(row=0, column=0, rowspan=2, sticky="nsew", padx=(0, 12), pady=(0, 12))
        left_frame.columnconfigure(0, weight=1)
        left_frame.rowconfigure(1, weight=1)

        # Inner frame for the listbox with border
        listbox_frame = tk.Frame(left_frame, bg=self.bg_primary, bd=2, relief=tk.SUNKEN)
        listbox_frame.grid(row=1, column=0, sticky="nsew", padx=2, pady=2)
        listbox_frame.columnconfigure(0, weight=1)
        listbox_frame.rowconfigure(0, weight=1)

        self.vm_listbox = tk.Listbox(
            listbox_frame,
            height=25,
            width=25,
            exportselection=False,
            font=('Consolas', 9),
            bg='#ffffff',
            fg=self.bg_primary,
            selectbackground=self.bg_accent,
            selectforeground='#ffffff',
            relief=tk.FLAT,
            bd=0,
            highlightthickness=0,
            activestyle='none'
        )
        self.vm_listbox.grid(row=0, column=0, sticky="nsew")
        scrollbar = ttk.Scrollbar(listbox_frame, orient="vertical", command=self.vm_listbox.yview)
        self.vm_listbox.config(yscrollcommand=scrollbar.set)
        scrollbar.grid(row=0, column=1, sticky="ns")

        for name in self.vm_names:
            self.vm_listbox.insert(tk.END, name)

        self.vm_listbox.bind("<<ListboxSelect>>", self._on_vm_select)

        # ===== RIGHT UPPER PANEL: OS Info fields =====
        info_frame = ttk.LabelFrame(
            main_frame,
            text="ℹ️  Operating System Information",
            padding=12
        )
        info_frame.grid(row=0, column=1, sticky="ew", padx=(0, 12), pady=(0, 12))
        info_frame.columnconfigure(1, weight=1)

        # Os_Family
        ttk.Label(info_frame, text="OS Family:", style='Header.TLabel').grid(row=0, column=0, sticky="e", padx=8, pady=8)
        self.entry_family = ttk.Entry(info_frame, width=40)
        self.entry_family.grid(row=0, column=1, sticky="ew", padx=8, pady=8)
        self.entry_family.configure(foreground=self.bg_primary)

        # OS Type
        ttk.Label(info_frame, text="OS Type:", style='Header.TLabel').grid(row=1, column=0, sticky="e", padx=8, pady=8)
        self.entry_type = ttk.Entry(info_frame, width=40)
        self.entry_type.grid(row=1, column=1, sticky="ew", padx=8, pady=8)
        self.entry_type.configure(foreground=self.bg_primary)

        # OS Version
        ttk.Label(info_frame, text="OS Version:", style='Header.TLabel').grid(row=2, column=0, sticky="e", padx=8, pady=8)
        self.entry_version = ttk.Entry(info_frame, width=40)
        self.entry_version.grid(row=2, column=1, sticky="ew", padx=8, pady=8)
        self.entry_version.configure(foreground=self.bg_primary)

        # ===== RIGHT LOWER PANEL: Commands output =====
        commands_frame = ttk.LabelFrame(
            main_frame,
            text="📋  Command Output (commands_execute.json)",
            padding=12
        )
        commands_frame.grid(row=1, column=1, sticky="nsew", padx=(0, 0))
        commands_frame.columnconfigure(0, weight=1)
        commands_frame.rowconfigure(0, weight=1)

        self.text_commands = tk.Text(
            commands_frame,
            wrap="word",
            height=20,
            font=('Courier New', 12),
            bg='#2c3e50',
            fg='#ecf0f1',
            insertbackground='#3498db',
            relief=tk.FLAT,
            bd=0,
            padx=10,
            pady=10,
            highlightthickness=2,
            highlightcolor=self.bg_accent,
            highlightbackground='#bdc3c7'
        )
        commands_scroll = ttk.Scrollbar(commands_frame, orient="vertical", command=self.text_commands.yview)
        self.text_commands.config(yscrollcommand=commands_scroll.set, state="disabled")
        self.text_commands.grid(row=0, column=0, sticky="nsew", padx=2, pady=2)
        commands_scroll.grid(row=0, column=1, sticky="ns")

        # ===== BOTTOM PANEL: Buttons =====
        buttons_frame = tk.Frame(main_frame, bg='#ecf0f1')
        buttons_frame.grid(row=2, column=0, columnspan=2, sticky="ew", pady=(12, 0))
        buttons_frame.columnconfigure(0, weight=1)
        buttons_frame.columnconfigure(1, weight=0)

        # Navigation buttons
        nav_frame = tk.Frame(buttons_frame, bg='#ecf0f1')
        nav_frame.pack(side=tk.LEFT, fill=tk.X, expand=True)

        self.btn_prev = tk.Button(
            nav_frame,
            text="◀  Previous",
            command=self._prev_vm,
            width=14,
            font=('Helvetica', 10, 'bold'),
            bg=self.bg_info,
            fg=self.text_light,
            activebackground=self.bg_primary,
            activeforeground=self.text_light,
            relief=tk.FLAT,
            bd=0,
            highlightthickness=0,
            cursor='hand2',
            padx=10,
            pady=8
        )
        self.btn_prev.pack(side=tk.LEFT, padx=5)

        self.btn_reload = tk.Button(
            nav_frame,
            text="🔄  Reload",
            command=self._reload_current,
            width=14,
            font=('Helvetica', 10, 'bold'),
            bg='#e74c3c',
            fg=self.text_light,
            activebackground=self.bg_primary,
            activeforeground=self.text_light,
            relief=tk.FLAT,
            bd=0,
            highlightthickness=0,
            cursor='hand2',
            padx=10,
            pady=8
        )
        self.btn_reload.pack(side=tk.LEFT, padx=5)

        self.btn_next = tk.Button(
            nav_frame,
            text="Next  ▶",
            command=self._next_vm,
            width=14,
            font=('Helvetica', 10, 'bold'),
            bg=self.bg_info,
            fg=self.text_light,
            activebackground=self.bg_primary,
            activeforeground=self.text_light,
            relief=tk.FLAT,
            bd=0,
            highlightthickness=0,
            cursor='hand2',
            padx=10,
            pady=8
        )
        self.btn_next.pack(side=tk.LEFT, padx=5)

        # Save button (highlighted on the right)
        self.btn_save = tk.Button(
            buttons_frame,
            text="💾  Save os_info.json",
            command=self._save_os_info,
            font=('Helvetica', 11, 'bold'),
            bg=self.bg_success,
            fg=self.text_light,
            activebackground=self.bg_primary,
            activeforeground=self.text_light,
            relief=tk.FLAT,
            bd=0,
            highlightthickness=0,
            cursor='hand2',
            padx=15,
            pady=10
        )
        self.btn_save.pack(side=tk.RIGHT, padx=5)

    def _on_vm_select(self, event):
        if not self.vm_names:
            return
        sel = self.vm_listbox.curselection()
        if not sel:
            return
        index = sel[0]
        self._select_vm(index)

    def _select_vm(self, index: int):
        if index < 0 or index >= len(self.vm_names):
            return
        self.current_index = index
        self.vm_listbox.selection_clear(0, tk.END)
        self.vm_listbox.selection_set(index)
        self.vm_listbox.see(index)

        vm_name = self.vm_names[index]
        vm_dir = os.path.join(OS_INFO_BASE, vm_name)

        # Load os_info.json
        family = type_ = version = ""
        os_info_path = os.path.join(vm_dir, "os_info.json")
        if os.path.isfile(os_info_path):
            try:
                with open(os_info_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                family = str(data.get("Os_Family", ""))
                type_ = str(data.get("Os_Type", ""))
                version = str(data.get("Os_Version", ""))
            except Exception as e:
                messagebox.showerror("Error", f"Could not read {os_info_path}: {e}")

        self.entry_family.delete(0, tk.END)
        self.entry_family.insert(0, family)
        self.entry_type.delete(0, tk.END)
        self.entry_type.insert(0, type_)
        self.entry_version.delete(0, tk.END)
        self.entry_version.insert(0, version)

        # Load commands_execute.json
        commands_path = os.path.join(vm_dir, "commands_execute.json")
        commands_text = ""
        if os.path.isfile(commands_path):
            try:
                with open(commands_path, "r", encoding="utf-8") as f:
                    commands_data = json.load(f)
                commands_text = json.dumps(commands_data, indent=4, ensure_ascii=False)
            except Exception as e:
                commands_text = f"Error reading {commands_path}: {e}"
        else:
            commands_text = "commands_execute.json not found for this machine."

        self._colorize_json(commands_text, vm_name)

    def _colorize_json(self, json_text, vm_name=None):
        """Format JSON text with proper line breaks (for Windows OS only)."""
        
        self.text_commands.config(state="normal")
        self.text_commands.delete("1.0", tk.END)
        
        # Check if this is a Windows machine
        is_windows = False
        if vm_name:
            vm_dir = os.path.join(OS_INFO_BASE, vm_name)
            os_info_path = os.path.join(vm_dir, "os_info.json")
            if os.path.isfile(os_info_path):
                try:
                    with open(os_info_path, "r", encoding="utf-8") as f:
                        data = json.load(f)
                    os_family = str(data.get("Os_Family", "")).lower()
                    is_windows = "windows" in os_family
                except Exception:
                    pass
        
        # Ensure proper formatting with indentation
        try:
            parsed = json.loads(json_text)
            json_text = json.dumps(parsed, indent=4, ensure_ascii=False)
        except:
            pass
        
        # Replace literal \n with actual newlines only for Windows
        if is_windows:
            json_text = json_text.replace('\\n', '\n')
        
        # Insert formatted text
        self.text_commands.insert(tk.END, json_text)
        
        self.text_commands.config(state="disabled")

    def _current_vm_name(self):
        if self.current_index is None:
            return None
        if not (0 <= self.current_index < len(self.vm_names)):
            return None
        return self.vm_names[self.current_index]

    def _save_os_info(self):
        vm_name = self._current_vm_name()
        if not vm_name:
            return
        vm_dir = os.path.join(OS_INFO_BASE, vm_name)
        os.makedirs(vm_dir, exist_ok=True)
        os_info_path = os.path.join(vm_dir, "os_info.json")

        # Read current traffic folder from vm_info (if it exists), so we can
        # remove the old traffic directory when OS identification changes.
        old_traffic_folder = ""
        vm_info_path = os.path.join(VM_INFO_BASE, f"{vm_name}.json")
        if os.path.isfile(vm_info_path):
            try:
                with open(vm_info_path, "r", encoding="utf-8") as f:
                    vm_info = json.load(f)
                old_traffic_folder = vm_info.get("traffic_folder") or ""
            except Exception:
                old_traffic_folder = ""

        data = {
            "Os_Family": self.entry_family.get().strip(),
            "Os_Type": self.entry_type.get().strip(),
            "Os_Version": self.entry_version.get().strip(),
        }
        try:
            with open(os_info_path, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=4, ensure_ascii=False)
        except Exception as e:
            messagebox.showerror("Error", f"Could not save {os_info_path}: {e}")
            return

        vmuser = "vmuser"
        path_scripts = "scripts"
        os_family = data["Os_Family"]
        os_type = data["Os_Type"]
        os_version = data["Os_Version"]

        os.removedirs(old_traffic_folder) if old_traffic_folder and os.path.isdir(old_traffic_folder) else None

        inner_cmd = (
            f"./{path_scripts}/update_info_file.sh "
            f"{shlex.quote(vm_name)} "
            f"-f {shlex.quote(os_family)} "
            f"-t {shlex.quote(os_type)} "
            f"-v {shlex.quote(os_version)}"
        )

        try:
            result = subprocess.run(
                ["su", "-", vmuser, "-c", inner_cmd],
                check=True,
                text=True,
                capture_output=True,
            )
        except subprocess.CalledProcessError as e:
            messagebox.showwarning(
                "Update info",
                f"update_info_file.sh failed:\n{e.stderr}",
            )

    def _next_vm(self):
        if not self.vm_names or self.current_index is None:
            return
        next_index = self.current_index + 1
        if next_index >= len(self.vm_names):
            next_index = 0
        self._select_vm(next_index)

    def _prev_vm(self):
        if not self.vm_names or self.current_index is None:
            return
        prev_index = self.current_index - 1
        if prev_index < 0:
            prev_index = len(self.vm_names) - 1
        self._select_vm(prev_index)

    def _reload_current(self):
        if self.current_index is not None:
            self._select_vm(self.current_index)
