#!/usr/bin/env bash
# procesjaar.sh — haalt alle dagen van één jaar op via cargo run
# Gebruik: ./procesjaar.sh 2026 [extra args voor cargo run]

set -u

source setenv.bash

# Definieer de exit codes analoog aan de Rust constanten
readonly QUOTA=3
readonly FOUT=1
readonly GEEN_DATA=2

JAAR="${1:?Gebruik: $0 <jaar> [extra args]}"
shift                          # rest van de args gaat 1-op-1 naar cargo run

cd "$(dirname "$0")"           # vanuit de scriptmap naar het project
# cd ~/Develop/knmiweer        # of hardcode het projectpad

for MAAND in $(seq 1 12); do
    for DAG in $(seq 1 31); do
        DATUM=$(printf '%04d-%02d-%02d' "$JAAR" "$MAAND" "$DAG")

        # Sla onbestaande datums over (30 feb, 31 apr, ...)
        if ! date -d "$DATUM" '+%Y-%m-%d' > /dev/null 2>&1; then
            continue
        fi

        echo "=== $DATUM ==="
        cargo run -- --date "$DATUM" "$@"
        EXIT_CODE=$?
        
        # Controleer op specifieke exit codes
        case "$EXIT_CODE" in
            "$QUOTA")
                echo "[-] Quota limiet bereikt (exit code $QUOTA). Script gestopt op $DATUM." >&2
                exit "$QUOTA"
                ;;
            "$FOUT")
                echo "[-] Fout opgetreden (exit code $FOUT). Script gestopt op $DATUM." >&2
                exit "$FOUT"
                ;;
            "$GEEN_DATA")
                echo "[-] Geen data beschikbaar (exit code $GEEN_DATA). Script gaat door naar de volgende datum." >&2
                ;;
            0)
                # Succes, ga door naar de volgende datum
                ;;
            *)
                # Optioneel: ook stoppen bij overige onverwachte fouten
                echo "[-] Onverwachte exit code ($EXIT_CODE). Script gestopt." >&2
                exit "$EXIT_CODE"
                ;;
        esac
    done
done