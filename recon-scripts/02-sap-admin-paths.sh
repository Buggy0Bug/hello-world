#!/bin/bash
# AS Watson / Marionnaud — SAP Commerce Cloud Admin Path Probing
# Tests for exposed Hybris admin consoles and OCC API
# Max 5 req/sec

OUTPUT="results/sap-admin-paths.txt"
mkdir -p results

SITES=(
  www.marionnaud.fr www.marionnaud.at www.marionnaud.ch www.marionnaud.it
  www.marionnaud.hu www.marionnaud.cz www.marionnaud.ro www.marionnaud.sk
)

PATHS=(
  /hac/
  /hac/login.jsp
  /backoffice/
  /backoffice/login.zul
  /smartedit/
  /hmc/
  /solrfacetsearch/
  /virtualjdbc/
  /monitoring/
  /console/
  /occ/v2/
  /occ/v2/swagger-ui/index.html
  /rest/
  /medias/
  /_ui/
  /crm/
  /bcm/
  /test
  /.env
  /.git/HEAD
  /.well-known/security.txt
  /.well-known/openid-configuration
  /admin
  /login
  /graphql
)

echo "=== SAP Admin Path Probing — $(date) ===" > "$OUTPUT"

for site in "${SITES[@]}"; do
  echo ""
  echo "====== $site ======" | tee -a "$OUTPUT"
  for path in "${PATHS[@]}"; do
    status=$(curl -s -o /dev/null -w "%{http_code}|%{redirect_url}|%{size_download}" -m 10 "https://$site$path")
    code=$(echo "$status" | cut -d'|' -f1)
    redirect=$(echo "$status" | cut -d'|' -f2)
    size=$(echo "$status" | cut -d'|' -f3)

    if [ "$code" != "404" ] && [ "$code" != "000" ]; then
      echo "  [${code}] ${path} (${size}B) ${redirect}" | tee -a "$OUTPUT"
    else
      echo "  [${code}] ${path}" >> "$OUTPUT"
    fi
    sleep 0.25
  done
done

echo ""
echo "Results saved to $OUTPUT"
