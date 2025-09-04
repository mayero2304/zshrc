source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# --- Zinit bootstrap ---
if [[ ! -f $HOME/.local/share/zinit/zinit.git/zinit.zsh ]]; then
  mkdir -p "$HOME/.local/share/zinit" && chmod g-rwX "$HOME/.local/share/zinit"
  git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git"
fi
source "$HOME/.local/share/zinit/zinit.git/zinit.zsh"
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit

# --- Opciones útiles ---
setopt autocd
setopt correct                # autocorrección leve de comandos
setopt histignoredups sharehistory
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000

# --- Prompt: Powerlevel10k (carga rapidísima) ---
# Habilita “instant prompt” antes de cargar cualquier otra cosa
if [[ -r /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme ]]; then
  typeset -g POWERLEVEL10K_INSTANT_PROMPT=quiet
  source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme
fi
# Carga config del prompt si existe (se creará tras el wizard)
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# --- Plugins con zinit ---
# Autosuggestions
zinit light zsh-users/zsh-autosuggestions

# Highlighting (elige uno)
# zinit light zsh-users/zsh-syntax-highlighting
zinit light zdharma-continuum/fast-syntax-highlighting  # recomendado

# Completions extra
zinit light zsh-users/zsh-completions

# Búsqueda por subcadena en el historial (↑/↓) y con Ctrl+R
zinit light zsh-users/zsh-history-substring-search

# (Opcional) Sugerencias "deberías usar"
# zinit light MichaelAquilina/zsh-you-should-use

# --- Teclas útiles ---
# Hist substring search con flechas
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# --- Alias útiles ---
alias ll='ls -lah'
alias grep='grep --color=auto'

# --- Fuente Nerd por defecto para terminals que respetan~/.zshrc (alacritty lo configuras aparte) ---
export ZSH_TMUX_AUTOSTART=false
# Rust / Cargo
export CARGO_HOME="$HOME/.cargo"
export RUSTUP_HOME="$HOME/.rustup"
if [ -f "$CARGO_HOME/env" ]; then
  . "$CARGO_HOME/env"
else
  export PATH="$CARGO_HOME/bin:$PATH"
fi

eval "$(mise activate zsh)"

# Auto-tmux: adjunta a 'main' o créala si no existe; evita VSCode y sesiones anidadas
if command -v tmux >/dev/null 2>&1; then
  if [[ -z "$TMUX" && "$TERM_PROGRAM" != "vscode" ]]; then
    tmux attach -t main 2>/dev/null || tmux new -s main
  fi
fi

# ---- Listado robusto de entradas de pass (con/sin --flat) ----
__pass_list() {
  # 1) Si tu pass soporta --flat, úsalo
  if pass ls --flat >/dev/null 2>&1; then
    pass ls --flat
    return
  fi

  # 2) Fallback robusto: leer el password store del disco
  local store="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
  if [[ ! -d "$store" ]]; then
    return 0
  fi

  # Lista todos los .gpg, imprime ruta relativa y quita la extensión
  # (GNU find en Arch soporta -printf)
  find "$store" -type f -name '*.gpg' -printf '%P\n' | sed 's/\.gpg$//'
}

passmenu() {
  local entries entry
  entries="$(__pass_list)"
  [[ -z "$entries" ]] && { echo "No hay entradas en pass. Usa: pass insert <ruta>"; return 1; }
  entry="$(echo "$entries" | fzf --height 60% --reverse --prompt='pass> ')" || return
  pass show "$entry"
}

passui() {
  local entries
  entries="$(__pass_list)"
  [[ -z "$entries" ]] && { echo "No hay entradas en pass. Usa: pass insert <ruta>"; return 1; }
  echo "$entries" | fzf \
    --height 60% --reverse --prompt='pass> ' --border \
    --preview '
      c="$(pass show {} 2>/dev/null)";
      first="$(printf "%s\n" "$c" | sed -n "1p")";
      second="$(printf "%s\n" "$c" | sed -n "2,/^$/p" | sed -n "/./{p;q}")";
      user="$(printf "%s\n" "$c" | awk "BEGIN{IGNORECASE=1} /^user:[[:space:]]*/{sub(/^[Uu]ser:[[:space:]]*/,\"\"); print; exit}")";
      if [ -z "$user" ] && printf "%s" "$first" | grep -Eq "^[^[:space:]]+@[^[:space:]]+$"; then user="$first"; fi
      [ -z "$user" ] && user="(sin user)";
      pass_line="$(printf "%s\n" "$c" | awk "BEGIN{IGNORECASE=1} /^pass(word)?:[[:space:]]*/{sub(/^pass(word)?:[[:space:]]*/,\"\"); print; exit}")";
      if [ -z "$pass_line" ]; then
        if printf "%s" "$first" | grep -Eq "^[^[:space:]]+@[^[:space:]]+$"; then pass_line="$second"; else pass_line="$first"; fi
      fi
      [ -z "$pass_line" ] && pass_line="(vacío)";
      pass_masked="$(printf "%s" "$pass_line" | cut -c1-2)***";
      printf "user: %s\npass: %s\n" "$user" "$pass_masked"
    ' \
    --preview-window=right:50%:wrap \
    --bind 'enter:execute-silent(pass -c {} >/dev/null)+abort' \
    --bind 'ctrl-y:execute-silent(pass show {} | awk "BEGIN{IGNORECASE=1} /^user:[[:space:]]*/{sub(/^[Uu]ser:[[:space:]]*/,\"\"); print; exit}" | xclip -selection clipboard >/dev/null)+abort' \
    --bind 'ctrl-e:execute(pass edit {})'
  [[ $? -eq 0 ]] && echo "✅ Contraseña copiada (se limpia sola en ~45s)."
}
passls() {
  local entries entry content first second user pass pass_masked

  entries="$(__pass_list)"
  [[ -z "$entries" ]] && { echo "No hay entradas en pass. Usa: pass insert <ruta>"; return 1; }

  printf "%-30s | %-28s | %s\n" "Entrada" "Usuario" "Contraseña"
  printf "%-30s-+-%-28s-+-%s\n" "------------------------------" "----------------------------" "----------------"

  while IFS= read -r entry; do
    content="$(pass show "$entry" 2>/dev/null)"
    first="$(printf "%s\n" "$content" | sed -n '1p')"
    second="$(printf "%s\n" "$content" | sed -n '2,/^$/p' | sed -n '/./{p;q}')"

    # user: prioridad a línea 'user:'
    user="$(printf "%s\n" "$content" | awk 'BEGIN{IGNORECASE=1} /^user:[[:space:]]*/{sub(/^[Uu]ser:[[:space:]]*/,""); print; exit}')"
    if [[ -z "$user" && "$first" == *"@"* && "$first" != *" "* ]]; then
      user="$first"
    fi
    [[ -z "$user" ]] && user="(sin user)"

    # password: password:/pass: > (si 1ª línea no es email) 1ª línea > (si 1ª es email) 2ª no vacía
    pass="$(printf "%s\n" "$content" | awk 'BEGIN{IGNORECASE=1} /^pass(word)?:[[:space:]]*/{sub(/^pass(word)?:[[:space:]]*/,""); print; exit}')"
    if [[ -z "$pass" ]]; then
      if [[ "$first" == *"@"* && "$first" != *" "* ]]; then
        pass="$second"
      else
        pass="$first"
      fi
    fi
    [[ -z "$pass" ]] && pass="(vacío)"

    pass_masked="${pass:0:2}***"
    printf "%-30s | %-28s | %s\n" "$entry" "$user" "$pass_masked"
  done <<< "$entries"
}
clear_screen() { clear; zle reset-prompt }
zle -N clear_screen
bindkey '^I' clear_screen   # Ctrl+I (pero pisa Tab)

