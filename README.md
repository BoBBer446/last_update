# last_update

`last_update` ist ein Bash-Skript bzw. eine Bash-Function, das Install- und Upgrade-Blöcke aus der Datei `/var/log/apt/history.log` extrahiert und farbig hervorhebt. Es zeigt alle Pakete, die in einem angegebenen Datums-Zeit-Intervall installiert, aktualisiert oder entfernt wurden, und berechnet für jeden Block eine ungefähre Dauer in Sekunden.

---

## Inhalt dieser Repository

- **`last_update.sh`**  
  Enthält die Bash-Function `last_update`, die in einer Shell-Umgebung ausgeführt werden kann.
- **`README.md`**  
  Diese Datei mit Installation-, Konfigurations- und Nutzungshinweisen.

---

## Voraussetzungen

- Ein Ubuntu- (oder Debian-)basiertes System mit installiertem `bash`.
- Leserechte auf `/var/log/apt/history.log` (üblicherweise als Root oder via `sudo`).
- Ein Terminal, das ANSI-Farbcodes unterstützt (die meisten modernen Terminals tun dies).

---

## Installation

### 1. Für einen einzelnen Benutzer

1. Kopiere den Inhalt von `last_update.sh` in Deine persönliche Bash-Konfigurationsdatei (`~/.bashrc` oder `~/.bash_profile`).  
   Am besten öffnest Du `~/.bashrc` in Deinem Lieblingseditor, z. B.:  
   ```bash
   nano ~/.bashrc
   ```

2. Füge ans Ende die gesamte `last_update`-Function aus `last_update.sh` ein. Achte darauf, dass der Block exakt übernommen wird. Beispiel:

   ```bash
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
   ```

3. Speichere die Datei und lade Deine Shell neu, damit die Function verfügbar wird:

   ```bash
   source ~/.bashrc
   ```

4. Prüfe im Terminal, ob `last_update` nun funktioniert.

   ```bash
   type last_update
   # Ausgabe sollte sein: last_update is a function
   ```

---

### 2. Systemweite Installation für alle Benutzer

Wenn Du die Funktion systemweit für **alle** Benutzer verfügbar machen möchtest, kopiere den Block aus `last_update.sh` in eine globale Bash-Konfigurationsdatei, z. B.:

```bash
sudo nano /etc/bash.bashrc
```

Füge dort am Ende denselben Function-Block ein:

```bash
# -----------------------------------------------------------------------------
# Function: last_update (global verfügbar)
# -----------------------------------------------------------------------------
last_update() {
    # ... (gleicher Inhalt wie oben) ...
}
# -----------------------------------------------------------------------------
```

Dann müssen sich alle Benutzer, die eine neue Shell öffnen, nicht mehr selbst in ihre `~/.bashrc` eintragen. Sobald sie eine neue Sitzung starten bzw. eine Shell öffnen, ist `last_update` automatisch verfügbar.

---

## Verwendung

Nach der Installation (sowohl pro Benutzer als auch systemweit) rufst Du das Skript wie folgt auf:

```bash
last_update "START_DATUM UHRZEIT" "END_DATUM UHRZEIT"
```

* `START_DATUM UHRZEIT` und `END_DATUM UHRZEIT` im Format `DD.MM.YYYY HH:MM` **oder** alternativ `DD-MM-YYYY HH:MM`
* Beispiel:

  ```bash
  last_update "29.05.2025 06:40" "31.05.2025 11:45"
  ```

Das Skript:

1. Parst die beiden Eingabe-Strings und wandelt sie in das ISO-Format `YYYY-MM-DD HH:MM:SS` um.
2. Rechnet diese Strings in Unix-Timestamps (Epoch-Sekunden).
3. Rechnet die Timestamps zurück in AWK-kompatible Strings (`YYYY-MM-DD` und `HH:MM:SS`).
4. Läuft mit `awk` durch `/var/log/apt/history.log` und sammelt jede `Start-Date:`- bis `End-Date:`-Block.
5. Gibt nur jene Blöcke aus, die zumindest teilweise im angegebenen Datums-/Zeit-Fenster liegen.
6. Berechnet für jeden Block eine `Dauer: X Sekunden`.
7. Leitet das Ergebnis an `sed` weiter, um wichtige Zeilen farblich hervorzuheben:

   * `Start-Date:` und `End-Date:` in Cyan (fett)
   * `Commandline:` in Grün (fett)
   * `Requested-By:` in Magenta (fett)
   * `Install:`, `Upgrade:`, `Remove:` in Blau (fett)
   * `Dauer:` in Gelb (fett)

### Beispielausgabe (farbig hervorgehoben)

```bash
$ last_update "29.05.2025 06:40" "31.05.2025 11:45"
```

* **Cyan** (fett) → `Start-Date: …` / `End-Date: …`
* **Grün** (fett) → `Commandline: …`
* **Magenta** (fett) → `Requested-By: …`
* **Blau** (fett) → `Install: …`, `Upgrade: …`, `Remove: …`
* **Gelb** (fett) → `Dauer: … Sekunden`

So kannst Du auf einen Blick sehen, wann welche Pakete installiert oder aktualisiert wurden, von wem der Befehl ausgeführt wurde und wie lange der Vorgang gedauert hat.

---

## Beispiel

```bash
# Per-User-Installation
nano ~/.bashrc
# (Füge Function ein, speichere und ~ nach dem Speichern:)
source ~/.bashrc

# Oder systemweit (Root-Rechte benötigt):
sudo nano /etc/bash.bashrc
# (Füge Function ein, speichere)
# Ab jetzt ist last_update in jeder neuen Shell verfügbar.

# Nutzung
last_update "30.05.2025 08:00" "30.05.2025 10:00"
```

**Mögliche farbige Ausgabe** (hier nur illustrativ als Text, Farben erscheinen im Terminal):

```
Start-Date: 2025-05-30  08:15:12
Commandline: apt-get install nginx
Install: nginx:amd64 (1.18.0-0ubuntu1)
End-Date: 2025-05-30  08:15:14
Dauer: 2 Sekunden

Start-Date: 2025-05-30  09:00:05
Commandline: unattended-upgrade
Upgrade: openssl:amd64 (1.1.1f-1ubuntu2.12, 1.1.1f-1ubuntu2.13)
End-Date: 2025-05-30  09:00:08
Dauer: 3 Sekunden
```

(In dieser Darstellung erscheinen die Schlüsselworte im tatsächlichen Terminal in den konfigurierten Farben.)

---

## Zusammenfassung

* **Installation pro Benutzer**:

  * Kopiere die Function in `~/.bashrc` oder `~/.bash_profile` und lade neu.
* **Installation systemweit**:

  * Füge die Function in `/etc/bash.bashrc` ein (Root-Rechte nötig).
* **Verwendung**:

  * `last_update "DD.MM.YYYY HH:MM" "DD.MM.YYYY HH:MM"` oder
    `last_update "DD-MM-YYYY HH:MM" "DD-MM-YYYY HH:MM"`.
* **Farbige Ausgabe**:

  * Start-/End-Datum in Cyan, Befehlszeile in Grün, Pakete in Blau, Dauer in Gelb.

Damit kannst Du schnell und übersichtlich nachvollziehen, welche Pakete in welchem Zeitrahmen auf Deinem Ubuntu-System installiert, aktualisiert oder entfernt wurden – sowohl einzeln als auch global für alle Benutzer. Viel Spaß damit!
