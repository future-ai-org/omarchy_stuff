# 🤪 Random Useful

<br>

---

### `.config/hypr/bindings.lua`

<br>

```
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

---

### `nvim ~/.config/omarchy/shell.json`

<br>

```shell
  "idle": {
    "screensaver": 1800,
    "lock": 1800,
  },
  {
    "id": "omarchy.clock",
          "format": "dddd d MMMM HH:mm",
  },
```

----

### pbcopy

<br>

```
sudo pacman -S wl-clipboard
wl-copy < FILE
```

<br>

---

### every fresh install...

<br>

#### keys

<br>

```
ssh-keygen -t ed25519 -C "email"
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
sudo pacman -S wl-clipboard
cat ~/.ssh/id_ed25519.pub | wl-copy
```

<br>

#### tmux

<br>

```
export TERMINAL=ghostty
sudo pacman -S tmux
```

witth `.tmux.conf`:

```
# split panes using | and -
bind | split-window -h
bind - split-window -v
unbind '"'
unbind %

# History
set -g history-limit 10000

# Terminal emulator window title
set -g set-titles on
set -g set-titles-string '[#S:#I.#H] #W'

# Status Bar
set-option -g status-bg white
set-option -g status-fg black

# Notifying if other windows has activities
setw -g monitor-activity off
set -g visual-activity on

# Clock
setw -g clock-mode-colour green
setw -g clock-mode-style 24

# make scrolling with wheels work
bind -n WheelUpPane if-shell -F -t = "#{mouse_any_flag}" "send-keys -M" "if -Ft= '#{pane_in_mode}' 'send-keys -M' 'select-pane -t=; copy-mode -e; send-keys -M'"

# Mouse Support
setw -g mouse

# Add SSH_TTY to the list of environment variables tmux knows about:
set-option -g update-environment "DISPLAY SSH_ASKPASS SSH_AGENT_PID SSH_CONNECTION WINDOWID XAUTHORITY SSH_TTY"

# Assume terminals want 256 colors
set-option -g default-terminal screen-256color

# Colors
# Status bar has a dim gray background
set-option -g status-bg black
set-option -g status-fg colour74

# Left shows the session name, in blue
set-option -g status-left-bg default
set-option -g status-left-fg colour74

# Right is some CPU stats, so terminal green
set-option -g status-right-bg default
set-option -g status-right-fg black
set -g status-right "Impossible is a State of Mind"

# statusbar
set -g status-position bottom
set -g status-justify left
set -g status-style 'bg=colour219 fg=colour137'
set -g status-left '#[fg=colour233,bg=colour219] %d/%m #[fg=colour233,bg=colour8] %H:%M:%S '
set -g status-right-length 50
set -g status-left-length 20

setw -g window-status-current-style 'fg=colour1 bg=colour219 bold'
setw -g window-status-current-format ' #I#[fg=colour249]:#[fg=colour255]#W#[fg=colour249]#F '

setw -g window-status-style 'fg=colour9 bg=colour219'
setw -g window-status-format ' #I#[fg=colour237]:#[fg=colour250]#W#[fg=colour244]#F '

setw -g window-status-bell-style 'fg=colour255 bg=colour1 bold'

# Highlighting the active window in status bar
setw -g window-status-current-bg colour234
setw -g window-status-current-fg colour71

# zsh
set-option -g default-shell ${SHELL}
set-option -g default-shell /bin/zsh

new-session
```
<br>

---

### hygiene

<br>

```
omarchy-pkg-remove 
```

<br>

```
nmcli connection show
nmcli connection delete "YOUR_SSID"
```

<br>

---

### default keybindings

<br>


- SUPER +/- for multi-window and `omarchy display text size 11`
- SUPER + f for maxxxx screen

<br>

---

### remove the claude icon from the omarchy bar

<br>

confirm that omarchy uses quickshell

```bash
pgrep -af 'quickshell|waybar|claude'
```

<br>

locate the agents plugin configuration

```bash
grep -RinE 'claude|tray' ~/.config/quickshell /usr/share/omarchy/shell 2>/dev/null | wl-copy
```

<br>

the relevant files included:

- `/usr/share/omarchy/shell/plugins/agents/main.qml`
- `/usr/share/omarchy/shell/plugins/agents/panel.qml`
- `/usr/share/omarchy/shell/plugins/agents/readme.md`
- `/usr/share/omarchy/shell/plugins/agents/manifest.json`

<br>

the plugin supports per-agent enablement through the `providers` configuration object.

```bash
omarchy bar set omarchy.agents providers '{"claude":{"enabled":false},"codex":{"enabled":true},"fireworks":{"enabled":true}}' --json
```

<br>

```bash
omarchy bar set omarchy.agents refreshIntervalSec 300 --json
```

<br>