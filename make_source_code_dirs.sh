tidal export apps | jq  '.[] | "\(.id)-\(.name)"' | tr '[:upper:]' '[:lower:]' | tr -s ' /()' '____' | xargs mkdir
