# 🤪 Useful

<br>

#### Small snippets and fixes I keep coming back to.

<br>

---

## Hyprland

<br>

### Workspace keys and the Omarchy menu

<br>

Put this in `~/.config/hypr/bindings.lua`. It moves workspace switching to `CTRL + LEFT/RIGHT` and the Omarchy menu to `CTRL + SPACE`, which frees `SUPER + SPACE` for the emoji picker.

```lua
hl.unbind("CTRL + LEFT")
hl.unbind("CTRL + RIGHT")

o.bind("CTRL + LEFT", "Previous workspace", hl.dsp.focus({ workspace = "e-1" }))
o.bind("CTRL + RIGHT", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))

hl.unbind("SUPER + SPACE")

o.bind("CTRL + SPACE", "Omarchy menu", { launch = "omarchy-menu" })
o.bind("SUPER + SPACE", "Emoji picker", {
    launch = "omarchy-shell shell toggle omarchy.emojis"
})
```

<br>

### Default keys

- `SUPER + F`: fullscreen

<br>

---

## Omarchy shell

<br>

### Idle timeouts and clock format

<br>

Edit with `nvim ~/.config/omarchy/shell.json`. This is a fragment: merge it into the existing objects rather than replacing the file. Times are in seconds.

```json
"idle": {
  "screensaver": 1800,
  "lock": 1800
},
...
{
  "id": "omarchy.clock",
  "format": "h:mm AP · dddd, MMMM d, yyyy",
  "formatAlt": "dddd, MMMM D, YYYY",
  "verticalFormat": "h:mm A"
}
```

<br>

---

## Shell and clipboard

<br>

Copy a file to the clipboard (Wayland):

```bash
sudo pacman -S wl-clipboard
wl-copy < FILE
```

<br>

---

## Fresh install

<br>

### SSH keys

<br>

```bash
ssh-keygen -t ed25519 -C "you@example.com"
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

sudo pacman -S wl-clipboard
cat ~/.ssh/id_ed25519.pub | wl-copy
```

<br>

### tmux

<br>

```bash
export TERMINAL=ghostty
sudo pacman -S tmux
```

Save as `~/.tmux.conf`. It sets `|` and `-` for splits, mouse support, and a pink status bar:

```tmux
# ~/.tmux.conf

# Panes: | splits side by side, - splits stacked
bind | split-window -h
bind - split-window -v
unbind '"'
unbind %

# Mouse (scroll, select, resize panes)
set -g mouse on

# History and titles
set -g history-limit 10000
set -g set-titles on
set -g set-titles-string '[#S:#I.#H] #W'

# Terminal
set -g default-terminal "tmux-256color"
set -g default-shell /bin/zsh
set -g update-environment "DISPLAY SSH_ASKPASS SSH_AGENT_PID SSH_CONNECTION WINDOWID XAUTHORITY SSH_TTY"

# Activity: visual hint only, no monitor-activity noise
setw -g monitor-activity off
set -g visual-activity on

# Status bar
set -g status-position bottom
set -g status-justify left
set -g status-style 'bg=colour219 fg=colour137'
set -g status-left '#[fg=colour233,bg=colour219] %d/%m #[fg=colour233,bg=colour8] %H:%M:%S '
set -g status-left-length 20
set -g status-right '#[fg=colour233,bg=colour219] Impossible is a State of Mind '
set -g status-right-length 50

setw -g window-status-current-style 'fg=colour1 bg=colour219 bold'
setw -g window-status-current-format ' #I#[fg=colour249]:#[fg=colour255]#W#[fg=colour249]#F '
setw -g window-status-style 'fg=colour9 bg=colour219'
setw -g window-status-format ' #I#[fg=colour237]:#[fg=colour250]#W#[fg=colour244]#F '
setw -g window-status-bell-style 'fg=colour255 bg=colour1 bold'

# Clock
setw -g clock-mode-colour green
setw -g clock-mode-style 24
```

Reload after editing with `tmux source-file ~/.tmux.conf`.

<br>

---

## Maintenance

<br>

### Remove a package

<br>

```bash
omarchy-pkg-remove PACKAGE
```

<br>

### Remove a saved Wi-Fi network

<br>

```bash
nmcli connection show
nmcli connection delete "YOUR_SSID"
```

<br>

---

## Display

<br>

Set the UI text size:

```bash
omarchy display text size 11
```
