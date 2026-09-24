#!/bin/bash
# AS Watson / Marionnaud — Certificate Transparency Log Enumeration
# Queries crt.sh for all Marionnaud TLDs

OUTPUT="results/ct-logs.txt"
mkdir -p results

TLDS=(fr at ch it hu cz ro sk com de es paris)

echo "=== Certificate Transparency Log Enumeration — $(date) ===" > "$OUTPUT"

for tld in "${TLDS[@]}"; do
  echo ""
  echo "=== marionnaud.$tld ===" | tee -a "$OUTPUT"

  result=$(curl -s -m 30 "https://crt.sh/?q=%25.marionnaud.$tld&output=json")

  if [ -z "$result" ] || echo "$result" | grep -q "error"; then
    echo "  [FAILED] Could not query crt.sh" | tee -a "$OUTPUT"
  else
    subdomains=$(echo "$result" | jq -r '.[].common_name, .[].name_value' 2>/dev/null | \
      tr ',' '\n' | sed 's/\*\.//g' | sort -u | grep -v '^\*')
    count=$(echo "$subdomains" | wc -l)
    echo "  Found $count unique entries" | tee -a "$OUTPUT"
    echo "$subdomains" >> "$OUTPUT"
  fi

  sleep 2
done

echo ""
echo "Results saved to $OUTPUT"
echo ""
echo "=== NOVEL SUBDOMAINS (not in known scope) ==="
echo "Known: www, app, api, media, campaign, ecom-data, jeux-concours, bdes-api, bdese, extranet"
echo "Check $OUTPUT for any subdomains not in the above list"
