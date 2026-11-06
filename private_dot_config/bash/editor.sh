# Pick $EDITOR from preference lists, first one installed wins.
# Each entry is the full command; the first word is what gets looked up.
gui_editors="codium -n -w|code -w|geany|gedit"
tui_editors="hx|nvim|micro|edit|vim|vi"

pick_editor() {
  _list=$1
  _old_ifs=$IFS
  IFS='|'
  for _e in $_list; do
    if command -v "${_e%% *}" >/dev/null 2>&1; then
      export EDITOR="$_e"
      break
    fi
  done
  IFS=$_old_ifs
  unset _list _old_ifs _e
}

# Inside zellij or yazi, stay in the terminal and skip GUI editors.
if [ -z "$ZELLIJ" ] && [ -z "$YAZI_ID" ] && [ -z "$YAZI_LEVEL" ] && xset -q >/dev/null 2>&1; then
  pick_editor "$gui_editors"
fi
[ -z "$EDITOR" ] && pick_editor "$tui_editors"
[ -z "$EDITOR" ] && export EDITOR=vi

unset gui_editors tui_editors
unset -f pick_editor
