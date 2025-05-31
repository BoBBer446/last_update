# -----------------------------------------------------------------------------
# Function: last_update
# Zweck:   Aus /var/log/apt/history.log alle Install/Upgrade-Blöcke ausgeben,
#          die zumindest teilweise in ein gegebenes Datum-Zeit-Intervall fallen.
#          Für jeden Block wird eine ungefähre Dauer (in Sekunden) berechnet und
#          farbig hervorgehoben.
# -----------------------------------------------------------------------------
last_update() {
    # 1) Prüfen, ob genau 2 Argumente übergeben wurden
    if [ "$#" -ne 2 ]; then
        cat <<EOF
Usage: last_update "DD.MM.YYYY HH:MM" "DD.MM.YYYY HH:MM"
   oder: last_update "DD-MM-YYYY HH:MM" "DD-MM-YYYY HH:MM"
Beispiel: last_update "29.05.2025 06:40" "31.05.2025 11:45"
EOF
        return 1
    fi

    # 2) Hilfsfunktion: Wandelt "DD.MM.YYYY HH:MM" oder "DD-MM-YYYY HH:MM" in "YYYY-MM-DD HH:MM:SS" um
    parse_to_iso() {
        local input="$1"
        local datum="${input%% *}"    # "DD.MM.YYYY" oder "DD-MM-YYYY"
        local uhrzeit="${input#* }"   # "HH:MM"
        # Punkte durch Bindestriche ersetzen
        datum=$(echo "$datum" | sed -E 's/[.]/-/g')
        # Tag, Monat, Jahr extrahieren
        local tag="${datum%%-*}"
        local rest="${datum#*-}"
        local monat="${rest%%-*}"
        local jahr="${rest#*-}"
        # Ergebnis: "YYYY-MM-DD HH:MM:00"
        echo "${jahr}-${monat}-${tag} ${uhrzeit}:00"
    }

    # 3) Beide Roh-Strings konvertieren
    local raw_start="$1"
    local raw_end="$2"
    local start_iso end_iso
    start_iso=$(parse_to_iso "$raw_start")
    end_iso=$(parse_to_iso   "$raw_end")

    # 4) In Epoch (Sekunden seit 1970) umwandeln
    local start_epoch end_epoch
    start_epoch=$(date -d "$start_iso" +%s 2>/dev/null)
    end_epoch=$(date -d "$end_iso"   +%s 2>/dev/null)

    if [ -z "$start_epoch" ] || [ -z "$end_epoch" ]; then
        echo "Fehler: Ungültiges Datum/Zeit-Format nach Konvertierung."
        echo "       Stelle sicher, dass Du „DD.MM.YYYY HH:MM“ oder „DD-MM-YYYY HH:MM“ verwendest."
        return 1
    fi

    # 5) Beide Epochs zurück in ISO-Strings („YYYY-MM-DD“ und „HH:MM:SS“) für AWK
    local start_dt end_dt
    start_dt=$(date -d "@$start_epoch" +"%Y-%m-%d %H:%M:%S")
    end_dt=$(date -d "@$end_epoch"   +"%Y-%m-%d %H:%M:%S")

    local start_date="${start_dt%% *}"
    local start_time="${start_dt#* }"
    local end_date="${end_dt%% *}"
    local end_time="${end_dt#* }"

    # 6) AWK-Logik: Alle Blöcke sammeln, die zumindest teilweise ins Intervall fallen
    awk -v sd="$start_date" -v st="$start_time" \
        -v ed="$end_date"   -v et="$end_time" '
    function to_epoch(date, time) {
        split(date, D, "-")
        split(time, T, ":")
        return mktime(D[1] " " D[2] " " D[3] " " T[1] " " T[2] " " T[3])
    }
    BEGIN {
        start_ts = to_epoch(sd, st)
        end_ts   = to_epoch(ed, et)
        in_block       = 0
        block_start_ts = 0
        buf            = ""
    }
    /^Start-Date:/ {
        block_start_ts = to_epoch($2, $3)
        in_block = 1
        buf = $0 "\n"
        next
    }
    in_block && !/^End-Date:/ {
        buf = buf $0 "\n"
        next
    }
    /^End-Date:/ {
        block_end_ts = to_epoch($2, $3)
        buf = buf $0 "\n"
        if (block_start_ts <= end_ts && block_end_ts >= start_ts) {
            printf "%s", buf
            dur = block_end_ts - block_start_ts
            printf("Dauer: %d Sekunden\n\n", dur)
        }
        in_block = 0
        buf = ""
        next
    }
    ' /var/log/apt/history.log \
    | sed \
      -e $'s/^\\(Start-Date:.*\\)/\033[1;36m\\1\033[0m/' \
      -e $'s/^\\(End-Date:.*\\)/\033[1;36m\\1\033[0m/' \
      -e $'s/^\\(Commandline:.*\\)/\033[1;32m\\1\033[0m/' \
      -e $'s/^\\(Requested-By:.*\\)/\033[1;35m\\1\033[0m/' \
      -e $'s/^\\(Install:.*\\)/\033[1;34m\\1\033[0m/' \
      -e $'s/^\\(Upgrade:.*\\)/\033[1;34m\\1\033[0m/' \
      -e $'s/^\\(Remove:.*\\)/\033[1;34m\\1\033[0m/' \
      -e $'s/^\\(Dauer:.*\\)/\033[1;33m\\1\033[0m/'
}
# -----------------------------------------------------------------------------
