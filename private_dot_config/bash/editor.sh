if xset -q >/dev/null 2>&1 ; then
  if codium --version > /dev/null 2>&1; then
    export EDITOR="codium -n -w"
  elif code --version > /dev/null 2>&1; then
    export EDITOR="code -w"
  elif geany --version > /dev/null 2>&1; then
    export EDITOR="geany"
  elif gedit --version > /dev/null 2>&1; then
    export EDITOR="gedit"
  fi
fi
if [ -z "$EDITOR" ]; then
  if hx --version >/dev/null 2>&1; then
    export EDITOR=hx
  elif nvim --version >/dev/null 2>&1; then
    export EDITOR=nvim
  elif vim --version >/dev/null 2>&1; then
    export EDITOR=vim
  else
    export EDITOR=vi
  fi
fi
