# 🦹 [Zed](https://github.com/zed-industries/zed) Stuff

<br>

---

## Extensions

<br>

- [Dracula](https://draculatheme.com/zed)

---

## settings.json

<br>

Open with `zed: open settings` (or `~/.config/zed/settings.json`). Theme: `Dracula Solid`, Vim mode on, VSCode keymap.

```json
{
  "use_system_window_tabs": false,
  "preview_tabs": {
    "enable_keep_preview_on_code_navigation": false,
    "enable_preview_file_from_code_navigation": true,
    "enable_preview_multibuffer_from_code_navigation": false,
    "enable_preview_from_multibuffer": true,
    "enable_preview_from_file_finder": false,
    "enable_preview_from_project_panel": true,
    "enabled": true
  },
  "tabs": {
    "show_close_button": "always",
    "file_icons": true,
    "git_status": false
  },
  "tab_bar": {
    "show_pinned_tabs_in_separate_row": false,
    "show_tab_bar_buttons": true,
    "show_nav_history_buttons": false,
    "show": true
  },
  "title_bar": {
    "show_menus": false,
    "show_user_picture": false,
    "show_user_menu": true,
    "show_onboarding_banner": true,
    "show_sign_in": false,
    "show_project_items": true,
    "show_worktree_name": true,
    "show_branch_name": true,
    "show_branch_status_icon": false
  },
  "debugger": {
    "button": true
  },
  "search": {
    "button": true
  },
  "diagnostics": {
    "button": true
  },
  "status_bar": {
    "show_active_file": false,
    "line_endings_button": false,
    "cursor_position_button": false,
    "active_language_button": true
  },
  "prettier": {
    "allowed": false
  },
  "auto_update": false,
  "telemetry": {
    "diagnostics": false,
    "metrics": false,
    "anthropic_retention": false
  },
  "use_system_path_prompts": true,
  "when_closing_with_no_tabs": "close_window",
  "accessible_mode": true,
  "ui_font_weight": 450.0,
  "buffer_font_weight": 450.0,
  "outline_panel": {
    "auto_fold_dirs": true,
    "auto_reveal_entries": true,
    "indent_size": 20.0,
    "git_status": true,
    "folder_icons": true,
    "file_icons": true,
    "default_width": 300.0,
    "button": true,
    "dock": "left"
  },
  "collaboration_panel": {
    "button": true,
    "dock": "left"
  },
  "agent": {
    "max_content_width": 850.0,
    "dock": "right",
    "favorite_models": [],
    "model_parameters": []
  },
  "git_panel": {
    "tree_view": false,
    "starts_open": false,
    "button": true,
    "dock": "left"
  },
  "colorize_brackets": true,
  "indent_guides": {
    "background_coloring": "disabled"
  },
  "which_key": {
    "enabled": false
  },
  "terminal": {
    "toolbar": {
      "breadcrumbs": false
    },
    "default_height": 250.0,
    "keep_selection_on_copy": true,
    "font_size": 10.0,
    "flexible": true,
    "button": true,
    "show_count_badge": false,
    "starts_open": true
  },
  "project_panel": {
    "auto_open": {
      "on_drop": true,
      "on_paste": true,
      "on_create": true
    },
    "hide_hidden": false,
    "hide_root": true,
    "drag_and_drop": true,
    "sticky_scroll": true,
    "diagnostic_badges": false,
    "git_status_indicator": true,
    "scrollbar": {
      "horizontal_scroll": true,
      "show": "always"
    },
    "bold_folder_labels": false,
    "starts_open": true,
    "auto_reveal_entries": true,
    "git_status": false,
    "folder_icons": true,
    "file_icons": true,
    "button": true,
    "hide_gitignore": false,
    "indent_size": 15.0,
    "entry_spacing": "standard",
    "default_width": 191.0,
    "dock": "left"
  },
  "cli_default_open_behavior": "existing_window",
  "agent_ui_font_size": 12.0,
  "ui_font_size": 12.0,
  "buffer_line_height": "standard",
  "proxy": "",
  "vim_mode": true,
  "base_keymap": "VSCode",
  "minimap": {
    "show": "never"
  },
  "cursor_shape": "block",
  "autosave": "on_focus_change",
  "buffer_font_size": 9.0,
  "show_whitespaces": "trailing",
  "soft_wrap": "editor_width",
  "theme": "Dracula Solid"
}
```

<br>

---

## Reminders

<br>

- `g /`: a shortcut I keep forgetting

<br>

---

## Agent integrations

<br>

- [Pi Agent](https://pi.dev/docs/latest/terminal-setup#zed-integrated-terminal)
- [Deep Agent](https://github.com/langchain-ai/deepagents/tree/main/libs/acp)
- [Ante Agent](https://github.com/AntigmaLabs/ante/tree/main/ante-acp)
- [Other agents](https://zed.dev/docs/ai/external-agents)
- [Persistent memory with Hindsight](https://hindsight.vectorize.io/blog/2026/07/07/zed-persistent-memory)
