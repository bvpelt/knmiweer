#!/usr/bin/env bash
# procesjaar.bash — haalt alle dagen van één jaar op via cargo run
# Gebruik: ./procesjaar.bash 2026 [extra args voor cargo run]

set -u

# Definieer de exit codes analoog aan de Rust constanten
readonly FOUT=1
readonly QUOTA=3
readonly GEEN_DATA=4
readonly STATE_FILE="knmi_state.json"

# Laad omgevingsvariabelen indien aanwezig
if [ -f "setenv.bash" ]; then
    source setenv.bash
fi

JAAR="${1:?Gebruik: $0 <jaar> [extra args]}"
shift                          # rest van de args gaat 1-op-1 naar cargo run

# Ga naar de juiste projectmap
cd "$(dirname "$0")" || exit 1
if [ -d ~/Develop/knmiweer ]; then
    cd ~/Develop/knmiweer
fi

# Bepaal de startdatum (ervat-logica op basis van knmi_state.json)
START_DATUM="${JAAR}-01-01"

if [ -f "$STATE_FILE" ]; then
    # Lees 'last_edr_day' uit de JSON (bijv. "2026-11-06")
    LAST_EDR=$(jq -r '.last_edr_day // empty' "$STATE_FILE" 2>/dev/null)
    
    if [ -n "$LAST_EDR" ]; then
        # Bereken de dag ná last_edr_day
        NEXT_DAY=$(date -d "$LAST_EDR + 1 day" '+%Y-%m-%d' 2>/dev/null)
        
        if [ -n "$NEXT_DAY" ]; then
            # Controleer of deze volgende dag binnen hetzelfde jaar valt
            NEXT_JAAR=$(date -d "$NEXT_DAY" '+%Y')
            if [ "$NEXT_JAAR" -eq "$JAAR" ]; then
                START_DATUM="$NEXT_DAY"
                echo "[*] Hervatten vanaf volgende dag: $START_DATUM (volgens $STATE_FILE)"
            elif [ "$NEXT_JAAR" -gt "$JAAR" ]; then
                echo "[*] Laatste opgeslagen datum valt in of na dit jaar ($JAAR). Klaar of geen dagen te doen."
                exit 0
            fi
        fi
    fi
fi

# Converteer START_DATUM naar maand en dag om de loops te sturen
START_MAAND=$(date -d "$START_DATUM" '+%m' | sed 's/^0//')
START_DAG=$(date -d "$START_DATUM" '+%d' | sed 's/^0//')

IN_START_PERIODE=true

for MAAND in $(seq 1 12); do
    # Sla maanden over die voor de startmaand liggen (bij hervatting)
    if [ "$IN_START_PERIODE" = true ] && [ "$MAAND" -lt "$START_MAAND" ]; then
        continue
    fi

    for DAG in $(seq 1 31); do
        # Sla dagen over in de startmaand die voor de startdag liggen
        if [ "$IN_START_PERIODE" = true ] && [ "$MAAND" -eq "$START_MAAND" ] && [ "$DAG" -lt "$START_DAG" ]; then
            continue
        else
            # Vanaf hier zijn we voorbij de startdatum, vlag uitzetten
            IN_START_PERIODE=false
        fi

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
                echo "[-] Geen data vastgelegd (exit code $GEEN_DATA). Script gaat door." >&2
                ;;
            0)
                # Succes, ga door naar de volgende datum
                ;;
            *)
                echo "[-] Onverwachte exit code ($EXIT_CODE). Script gestopt." >&2
                exit "$EXIT_CODE"
                ;;
        esac
    done
done

echo "[+] Jaar $JAAR succesvol verwerkt."