case "$(uname -s | tr [:upper:] [:lower:])" in
linux*)
  declare -r PLATFORM=linux
  ;;
darwin*)
  declare -r PLATFORM=darwin
  ;;
msys*|mingw*|cygwin*)
  declare -r PLATFORM=windows
  ;;
*)
  declare -r PLATFORM=unknown
  ;;
esac

function is_linux() {
  [[ "$PLATFORM" == "linux" ]]
}

function is_darwin() {
  [[ "$PLATFORM" == "darwin" ]]
}

function is_windows() {
  [[ "$PLATFORM" == "windows" ]]
}

function add_to_bazelrc() {
    echo "$@" >> .bazelrc
}
