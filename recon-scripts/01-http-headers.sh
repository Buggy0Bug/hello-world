#!/bin/bash
# AS Watson / Marionnaud — HTTP Header Recon
# Run from local machine with unrestricted network access
# Respects program rate limit: max 5 req/sec

OUTPUT="results/http-headers.txt"
mkdir -p results

DOMAINS=(
  # Tier 1
  www.marionnaud.fr app.marionnaud.fr api.marionnaud.fr media.marionnaud.fr
  www.marionnaud.at app.marionnaud.at api.marionnaud.at media.marionnaud.at
  www.marionnaud.ch app.marionnaud.ch api.marionnaud.ch media.marionnaud.ch
  www.marionnaud.it app.marionnaud.it api.marionnaud.it media.marionnaud.it
  # Tier 2
  www.marionnaud.hu app.marionnaud.hu api.marionnaud.hu media.marionnaud.hu
  www.marionnaud.cz app.marionnaud.cz api.marionnaud.cz media.marionnaud.cz
  www.marionnaud.ro app.marionnaud.ro api.marionnaud.ro media.marionnaud.ro
  www.marionnaud.sk app.marionnaud.sk api.marionnaud.sk media.marionnaud.sk
)

echo "=== HTTP Header Recon — $(date) ===" > "$OUTPUT"

for domain in "${DOMAINS[@]}"; do
  echo ""
  echo ">>> $domain" | tee -a "$OUTPUT"
  echo "--- HTTPS Headers ---" >> "$OUTPUT"
  curl -sI -m 10 -L "https://$domain" 2>&1 >> "$OUTPUT"
  echo "" >> "$OUTPUT"
  sleep 0.3
done

echo ""
echo "Results saved to $OUTPUT"
