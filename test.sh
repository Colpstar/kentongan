#!/bin/sh
# Sends a test notification and reports how long NotchProto took to capture it.
# NotchProto must already be running.
LOG="$HOME/Library/Logs/NotchProto.log"
BEFORE=$(grep -c "banner captured" "$LOG" 2>/dev/null)
BEFORE=${BEFORE:-0}
START=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
osascript -e 'display notification "Cek pulau di tengah atas" with title "Tes NotchProto"'
i=0
while [ $i -lt 50 ]; do
  NOW=$(grep -c "banner captured" "$LOG" 2>/dev/null)
  if [ "${NOW:-0}" -gt "$BEFORE" ]; then
    CAUGHT=$(grep "banner captured" "$LOG" | tail -1 | cut -d' ' -f1)
    echo "LOLOS: ketangkap $(echo "$CAUGHT - $START" | bc) detik setelah dikirim"
    exit 0
  fi
  perl -e 'select(undef, undef, undef, 0.2)'
  i=$((i + 1))
done
echo "GAGAL: belum ketangkap setelah 10 detik. Log terakhir:"
tail -40 "$LOG"
exit 1
