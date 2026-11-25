#!/usr/bin/env bash
# Split songs into 4 stems (vocals, drums, bass, other) for the DJ Studio.
#
#   tools/split-stems.sh song1.mp3 song2.mp3 ...
#   tools/split-stems.sh ~/Music/some-folder        # every song in the folder
#
# Each song lands in "$STEMS_DIR/<song name>/{vocals,drums,bass,other}.mp3".
# In the DJ Studio: My Music → "Add stems folder" → pick that folder.
# mp3/wav/flac/ogg work as-is; m4a/aac need ffmpeg (sudo apt update && sudo apt install ffmpeg). The first run downloads the model (~80 MB).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VENV="$HERE/.venv"
STEMS_DIR="${STEMS_DIR:-$HOME/Music/DJ Stems}"

if [ $# -eq 0 ]; then
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
fi

if ! "$VENV/bin/python" -c "import demucs" 2>/dev/null; then
  echo "Setting up Demucs (one time, CPU version)…"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q --upgrade pip
  "$VENV/bin/pip" install -q torch torchaudio --index-url https://download.pytorch.org/whl/cpu
  "$VENV/bin/pip" install -q demucs soundfile
fi

has_ffmpeg=1
command -v ffmpeg >/dev/null || has_ffmpeg=0

# Expand folders into the audio files inside them
songs=()
for arg in "$@"; do
  if [ -d "$arg" ]; then
    while IFS= read -r -d '' f; do songs+=("$f"); done < <(find "$arg" -maxdepth 1 -type f \
      \( -iname '*.mp3' -o -iname '*.wav' -o -iname '*.m4a' -o -iname '*.flac' -o -iname '*.ogg' -o -iname '*.aac' \) -print0)
  elif [ -f "$arg" ]; then
    songs+=("$arg")
  else
    echo "Not found: $arg"
    echo "Give the path to a song or to the folder your songs are in, e.g.: tools/split-stems.sh ~/Downloads"
    exit 1
  fi
done

if [ ${#songs[@]} -eq 0 ]; then
  echo "No songs (mp3, wav, m4a, flac, ogg, aac) found in: $*"
  exit 1
fi
# Without ffmpeg, turn mp3/flac/ogg into wav first (libsndfile reads those); m4a/aac still need ffmpeg
if [ $has_ffmpeg -eq 0 ]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  for i in "${!songs[@]}"; do
    f="${songs[$i]}"
    case "${f,,}" in
      *.wav) ;;
      *.mp3|*.flac|*.ogg)
        out="$tmp/$(basename "${f%.*}").wav"
        "$VENV/bin/python" -I -c 'import sys, soundfile as sf; d, sr = sf.read(sys.argv[1]); sf.write(sys.argv[2], d, sr)' "$f" "$out"
        songs[$i]="$out" ;;
      *)
        echo "ffmpeg is needed to read $(basename "$f"). Install it first: sudo apt update && sudo apt install ffmpeg"
        exit 1 ;;
    esac
  done
fi
echo "Splitting ${#songs[@]} song(s) — roughly 3x each song's length on this computer…"

mkdir -p "$STEMS_DIR"
"$VENV/bin/demucs" -n htdemucs --mp3 --mp3-bitrate 256 -o "$STEMS_DIR" \
  --filename "{track}/{stem}.{ext}" "${songs[@]}"

# Demucs nests output under the model name; flatten it to "<song>/<stem>.mp3"
if [ -d "$STEMS_DIR/htdemucs" ]; then
  cp -r "$STEMS_DIR/htdemucs/." "$STEMS_DIR/" && rm -rf "$STEMS_DIR/htdemucs"
fi

echo
echo "Done. Stems are in: $STEMS_DIR"
echo "DJ Studio → My Music → 🎛️ Add stems folder → pick that folder."
