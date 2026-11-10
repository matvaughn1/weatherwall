#!/bin/bash
C=/tmp/claude-1216800008/-home-mat/54178a8f-15f8-48df-82d0-99fda7c90d44/scratchpad/cands
run() { python3 "$(dirname "$0")/gather.py" "$C" "$@"; }
run yard_day "backyard" "garden house" "porch" "patio garden" "cottage garden"
run town_day "small town street" "village street" "main street" "old town" "neighborhood houses"
run town_night "town at night" "street at night" "village night" "house lights night" "street lamps"
run yard_snow "snowy backyard" "snowy garden" "snow house" "winter porch" "snowy cottage"
run town_snow "snowy street" "snowy town" "winter village" "snow city" "christmas street"
run yard_rain "rain garden" "rainy street" "rainy town" "rain window" "wet street"
