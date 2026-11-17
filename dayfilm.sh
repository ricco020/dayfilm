#!/usr/bin/env bash
# dayfilm.sh: turn a folder of phone clips into one "film of the day".
# Takes the first N seconds of every clip (default 2), in order of recording
# time, scales them to one portrait frame size and joins them into one MP4.
# Requires ffmpeg. Usage: ./dayfilm.sh <folder> [output.mp4] [seconds]
set -euo pipefail
dir="${1:?usage: dayfilm.sh <folder> [output.mp4] [seconds]}"
out="${2:-dayfilm.mp4}"
secs="${3:-2}"
FFMPEG="${FFMPEG:-ffmpeg}"
W="${W:-1080}"; H="${H:-1920}"; FPS="${FPS:-30}"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
i=0
# Oldest first (modification time), so the film follows the day.
while IFS= read -r -d '' line; do
  f="${line#* }"
  i=$((i+1))
  part="$tmp/$(printf '%04d' "$i").mp4"
  # Same size, frame rate, pixel format and audio layout for every part,
  # otherwise the concat step produces a broken file.
  "$FFMPEG" -nostdin -loglevel error -y -t "$secs" -i "$f" \
    -f lavfi -t "$secs" -i anullsrc=channel_layout=stereo:sample_rate=44100 \
    -filter_complex "[0:v]scale=$W:$H:force_original_aspect_ratio=increase,crop=$W:$H,fps=$FPS,format=yuv420p,setsar=1[v]" \
    -map "[v]" -map "0:a?" -map 1:a -map -1:a:1 \
    -c:v libx264 -preset veryfast -crf 20 -c:a aac -ar 44100 -ac 2 -shortest "$part" 2>/dev/null \
  || "$FFMPEG" -nostdin -loglevel error -y -t "$secs" -i "$f" \
    -f lavfi -t "$secs" -i anullsrc=channel_layout=stereo:sample_rate=44100 \
    -filter_complex "[0:v]scale=$W:$H:force_original_aspect_ratio=increase,crop=$W:$H,fps=$FPS,format=yuv420p,setsar=1[v]" \
    -map "[v]" -map 1:a -c:v libx264 -preset veryfast -crf 20 -c:a aac -ar 44100 -ac 2 -shortest "$part"
  printf "file '%s'\n" "$part" >> "$tmp/list.txt"
done < <(find "$dir" -maxdepth 1 -type f \( -iname '*.mp4' -o -iname '*.mov' -o -iname '*.m4v' -o -iname '*.3gp' -o -iname '*.webm' \) -printf '%T@ %p\0' | sort -z -n)

[ "$i" -gt 0 ] || { echo "no video clips found in $dir" >&2; exit 1; }
"$FFMPEG" -nostdin -loglevel error -y -f concat -safe 0 -i "$tmp/list.txt" -c copy -movflags +faststart "$out"
echo "$out: $i clips, about $((i*secs)) s"
