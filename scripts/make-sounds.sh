#!/bin/zsh
# Generates sound candidates with ElevenLabs sound effects: deep parrot calls for start and cancel,
# and an abstract chirp for stop. Then trims and levels them.
#
#     ELEVENLABS_API_KEY=... scripts/make-sounds.sh [out-dir]
#
# Writes start-1..3, stop-1..3 and cancel-1..3 to out-dir (default $TMPDIR/ParrotSounds) and plays
# them. Copy the ones you like to Parrot/Sounds/start.wav, stop.wav and cancel.wav.
set -euo pipefail
: "${ELEVENLABS_API_KEY:?Set ELEVENLABS_API_KEY}"
out="${1:-${TMPDIR:-/tmp}/ParrotSounds}"
mkdir -p "$out/raw"

typeset -A prompts
prompts[start]="A soft gentle low parrot coo, short and rounded, mellow and friendly, slightly rising, close mic, clean studio recording, no background noise, no reverb"
prompts[stop]="A gentle abstract synthesized bird chirp, soft sine tone with a quick pitch flick down, subtle and calm, minimal interface confirmation sound, clean, no background noise"
prompts[cancel]="A short deep low parrot grumble, descending, disappointed, close mic, clean studio recording, no background noise"
# How far to pitch each one down, how much low end to add, where to roll off the top, and the peak
# level. The start sound plays most, so it's the mildest call; the stop chirp stays unpitched and quiet.
typeset -A rates bass lowpass peaks
rates=(start 0.8 stop 1 cancel 0.8)
bass=(start 5 stop 0 cancel 5)
lowpass=(start 2800 stop 6000 cancel 5500)
peaks=(start -5 stop -9 cancel -5)

for kind in start stop cancel; do
  for i in 1 2 3; do
    curl -fsS -o "$out/raw/$kind-$i.mp3" https://api.elevenlabs.io/v1/sound-generation \
      -H "xi-api-key: $ELEVENLABS_API_KEY" -H "Content-Type: application/json" \
      -d "{\"text\": \"${prompts[$kind]}\", \"duration_seconds\": 0.6, \"prompt_influence\": 0.7}" &
  done
done
wait

for kind in start stop cancel; do
  for i in 1 2 3; do
    name="$kind-$i"
    # Trim the lead-in, pitch down, warm the low end, cap at 0.42 s with a fade, then set the peak.
    ffmpeg -hide_banner -loglevel error -y -i "$out/raw/$name.mp3" -af "silenceremove=start_periods=1:start_threshold=-40dB,asetrate=44100*${rates[$kind]},aresample=44100,bass=g=${bass[$kind]}:f=140,lowpass=f=${lowpass[$kind]},atrim=0:0.42,afade=t=in:d=0.02,afade=t=out:st=0.32:d=0.1,silenceremove=stop_periods=-1:stop_threshold=-50dB" -ac 1 "$out/raw/$name.wav"
    peak=$(ffmpeg -hide_banner -i "$out/raw/$name.wav" -af volumedetect -f null - 2>&1 | awk '/max_volume/{print $5}')
    ffmpeg -hide_banner -loglevel error -y -i "$out/raw/$name.wav" -af "volume=$(echo "${peaks[$kind]} - ($peak)" | bc -l)dB" -c:a pcm_s16le "$out/$name.wav"
    say -r 220 "$kind $i"; afplay "$out/$name.wav"; sleep 0.6
  done
done
echo "Wrote candidates to $out"
