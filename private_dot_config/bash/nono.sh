# Share the working directory with nono without the prompt, so
# `nono run --profile claude -- claude` needs no --allow-cwd. The access level
# still comes from the profile (workdir.access). Interactive shells only, so
# scripts and agents that call nono see the original behaviour.
command -v nono >/dev/null 2>&1 || return 0

nono() {
  case $1 in
    run|shell|wrap)
      _nono_sub=$1
      shift
      command nono "$_nono_sub" --allow-cwd "$@"
      _nono_rc=$?
      unset _nono_sub
      return $_nono_rc
      ;;
    *)
      command nono "$@"
      ;;
  esac
}
