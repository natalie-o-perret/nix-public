_clojure_completion() {
  local cur="${COMP_WORDS[COMP_CWORD]}"

  if [[ "$cur" == -* ]]; then
    mapfile -t COMPREPLY < <(
      compgen -W '-A -X -T -M -P -J -Sdeps -Spath -Stree -Scp -Srepro -Sforce -Sverbose -Sthreads -Strace -- --version -version -i --init -e --eval --report -m --main -r --repl -h -? --help' -- "$cur"
    )
  else
    _filedir
  fi
}

_earth_completion() {
  # Bash's external completion protocol expects both values in the environment.
  mapfile -t COMPREPLY < <(
    COMP_LINE="$COMP_LINE" COMP_POINT="$COMP_POINT" earth "${COMP_WORDS[0]}" "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD-1]}"
  )
}

_herdr_carapace_completion() {
  # Herdr's generated function expects the arguments Bash normally supplies.
  # shellcheck disable=SC1090
  source <(herdr completion bash)
  _herdr "${COMP_WORDS[0]}" "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD-1]}"
}

_npx_completion() {
  local cur="${COMP_WORDS[COMP_CWORD]}"

  if [[ "$cur" == -* ]]; then
    mapfile -t COMPREPLY < <(
      compgen -W '--package -c --call -w --workspace --workspaces --include-workspace-root --allow-scripts --strict-allow-scripts --dangerously-allow-all-scripts --help' -- "$cur"
    )
  else
    mapfile -t COMPREPLY < <(compgen -c -- "$cur")
  fi
}

_ocaml_completion() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local prev="${COMP_WORDS[COMP_CWORD-1]}"
  local line option options=()

  case "$prev" in
    -color)
      mapfile -t COMPREPLY < <(compgen -W 'auto always never' -- "$cur")
      return
      ;;
    -error-style)
      mapfile -t COMPREPLY < <(compgen -W 'contextual short' -- "$cur")
      return
      ;;
    -I|-H)
      _filedir -d
      return
      ;;
  esac

  if [[ "$cur" == -* ]]; then
    while IFS= read -r line; do
      [[ "$line" == '  -'* ]] || continue
      option="${line#  }"
      options+=("${option%% *}")
    done < <(ocaml -help 2>&1)
    mapfile -t COMPREPLY < <(compgen -W "${options[*]}" -- "$cur")
  else
    _filedir
  fi
}

_odin_completion() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local in_commands=0 line option subcommand
  COMPREPLY=()

  if [[ "$COMP_CWORD" == 1 || "${COMP_WORDS[1]}" == help && "$COMP_CWORD" == 2 ]]; then
    [[ "$COMP_CWORD" == 1 && help == "$cur"* ]] && COMPREPLY+=(help)
    while IFS= read -r line; do
      if [[ "$line" == Commands: ]]; then
        in_commands=1
        continue
      fi
      (( in_commands )) || continue
      [[ -n "$line" ]] || break
      [[ "$line" =~ ^$'\t'([a-z][a-z-]*)[[:space:]] ]] || continue
      [[ "${BASH_REMATCH[1]}" == "$cur"* ]] && COMPREPLY+=("${BASH_REMATCH[1]}")
    done < <(odin help)
    return
  fi

  if [[ "$cur" == -* ]]; then
    subcommand="${COMP_WORDS[1]}"
    while IFS= read -r line; do
      [[ "$line" =~ ^[[:space:]]+(-[^[:space:]]+) ]] || continue
      option="${BASH_REMATCH[1]}"
      option="${option%%<*}"
      [[ "$option" == "$cur"* ]] && COMPREPLY+=("$option")
    done < <(odin help "$subcommand")
  else
    _filedir
  fi
}

complete -o default -F _clojure_completion clj clojure
complete -o nospace -F _earth_completion earth earthly
complete -o default -F _herdr_carapace_completion herdr
complete -o default -F _npx_completion npx
complete -o default -F _ocaml_completion ocaml
complete -o default -F _odin_completion odin
