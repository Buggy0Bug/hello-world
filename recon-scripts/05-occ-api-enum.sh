#!/bin/bash
# AS Watson / Marionnaud — OCC REST API v2 Enumeration
# SAP Spartacus uses OCC API — map endpoints and check for auth issues
# Max 5 req/sec

OUTPUT="results/occ-api-enum.txt"
mkdir -p results

# baseSiteId candidates (SAP Commerce site identifiers)
SITE_IDS=(
  marionnaud-fr marionnaudfr marionnaud
  marionnaud-at marionnaudat
  marionnaud-ch marionnaudch
  marionnaud-it marionnaudit
  marionnaud-hu marionnaudhu
  marionnaud-cz marionnaudcz
  marionnaud-ro marionnaudro
  marionnaud-sk marionnaudsk
)

API_HOSTS=(
  www.marionnaud.fr
  api.marionnaud.fr
  www.marionnaud.at
  api.marionnaud.at
  www.marionnaud.ch
  api.marionnaud.ch
  www.marionnaud.it
  api.marionnaud.it
)

echo "=== OCC API v2 Enumeration — $(date) ===" > "$OUTPUT"

# Step 1: Find the OCC API root
echo ""
echo "--- Step 1: Finding OCC API root ---" | tee -a "$OUTPUT"
for host in "${API_HOSTS[@]}"; do
  for occ_path in "/occ/v2" "/rest/v2" "/api/v2"; do
    code=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "https://$host$occ_path/")
    if [ "$code" != "404" ] && [ "$code" != "000" ]; then
      echo "  [${code}] https://$host$occ_path/" | tee -a "$OUTPUT"
    fi
    sleep 0.25
  done
done

# Step 2: Find baseSiteId
echo ""
echo "--- Step 2: Finding baseSiteId ---" | tee -a "$OUTPUT"
for host in "www.marionnaud.fr" "api.marionnaud.fr"; do
  for site_id in "${SITE_IDS[@]}"; do
    code=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "https://$host/occ/v2/$site_id/languages")
    if [ "$code" != "404" ] && [ "$code" != "000" ] && [ "$code" != "403" ]; then
      echo "  [${code}] baseSiteId=$site_id on $host" | tee -a "$OUTPUT"
    fi
    sleep 0.25
  done
done

# Step 3: Enumerate API endpoints (once baseSiteId found — edit SITE below)
SITE="marionnaud-fr"
HOST="api.marionnaud.fr"

ENDPOINTS=(
  "/$SITE/languages"
  "/$SITE/currencies"
  "/$SITE/countries"
  "/$SITE/cardtypes"
  "/$SITE/catalogs"
  "/$SITE/products/search"
  "/$SITE/products/search?query=*&pageSize=5"
  "/$SITE/cms/pages"
  "/$SITE/cms/components"
  "/$SITE/users/anonymous"
  "/$SITE/users/current"
  "/$SITE/stores"
  "/$SITE/stores?pageSize=5"
  "/$SITE/consents/templates"
  "/$SITE/titles"
  "/$SITE/basesites"
  "/basesites"
)

echo ""
echo "--- Step 3: Enumerating API endpoints ($HOST) ---" | tee -a "$OUTPUT"
for endpoint in "${ENDPOINTS[@]}"; do
  response=$(curl -s -m 10 -w "\n%{http_code}" "https://$HOST/occ/v2$endpoint")
  code=$(echo "$response" | tail -1)
  body=$(echo "$response" | head -c 500)

  if [ "$code" != "404" ] && [ "$code" != "000" ]; then
    echo "" | tee -a "$OUTPUT"
    echo "  [${code}] /occ/v2$endpoint" | tee -a "$OUTPUT"
    echo "  Body (first 500 chars): $body" >> "$OUTPUT"
  fi
  sleep 0.3
done

# Step 4: Check Swagger
echo ""
echo "--- Step 4: Swagger UI ---" | tee -a "$OUTPUT"
for host in "${API_HOSTS[@]}"; do
  for swagger_path in "/occ/v2/swagger-ui/index.html" "/occ/v2/swagger-ui.html" "/api-docs" "/swagger-ui/" "/v2/api-docs" "/v3/api-docs"; do
    code=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "https://$host$swagger_path")
    if [ "$code" != "404" ] && [ "$code" != "000" ]; then
      echo "  [${code}] https://$host$swagger_path" | tee -a "$OUTPUT"
    fi
    sleep 0.25
  done
done

echo ""
echo "Results saved to $OUTPUT"
