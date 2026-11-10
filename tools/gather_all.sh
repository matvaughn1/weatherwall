#!/bin/bash
C=/tmp/claude-1216800008/-home-mat/54178a8f-15f8-48df-82d0-99fda7c90d44/scratchpad/cands
run() { python3 "$(dirname "$0")/gather.py" "$C" "$@"; }
run snow_night2 "cozy winter" "snowy house night" "christmas lights snow" "winter cabin lights"
run snow_day "snowy forest" "snow covered trees" "winter cabin snow" "snowy mountains village"
run clear_day "mountain lake" "alpine meadow" "mountain valley summer" "lake cabin"
run clear_night "milky way" "starry sky mountains" "moon lake night" "stars cabin"
run dusk "sunset mountains" "sunset lake" "golden hour valley" "dusk cabin"
run cloudy_day "cloudy mountains" "overcast lake" "moody landscape" "grey sky forest"
run rain_day "rain forest" "rainy day" "rain lake" "rain countryside"
run rain_night "rainy night city lights" "rain night street" "wet street night" "rain window night"
run fog "foggy forest" "mist morning lake" "fog mountains" "misty valley"
run storm "lightning storm" "thunderstorm" "storm clouds" "dramatic sky"
run autumn "autumn forest" "fall colors mountains" "autumn lake" "fall foliage"
run christmas "christmas lights" "christmas market" "christmas tree night" "festive village"
run halloween "pumpkins" "halloween" "autumn porch" "jack o lantern"
