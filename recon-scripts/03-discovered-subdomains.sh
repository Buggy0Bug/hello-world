#!/bin/bash
# AS Watson / Marionnaud — HTTP Probe Discovered Subdomains
# These were found via DNS but not yet HTTP-probed
# Max 5 req/sec

OUTPUT="results/discovered-subdomains.txt"
mkdir -p results

DOMAINS=(
  # BDES employee data (Priority 1)
  bdes-api.marionnaud.fr
  bdese.marionnaud.fr
  # UAT pre-production (Priority 2)
  uat.marionnaud.fr
  uat.marionnaud.at
  # CRM systems (Priority 3)
  crm.marionnaud.fr
  crm.marionnaud.it
  crm.marionnaud.at
  # IAST platform (Priority 4)
  extranet.marionnaud.ch
  # Legacy infrastructure (Priority 5)
  fs.marionnaud.fr
  sftp.marionnaud.fr
  newsletter.marionnaud.fr
  recrutement.marionnaud.fr
  pro.marionnaud.fr
  # On-prem French infra (Priority 6)
  static.marionnaud.fr
  webmail.marionnaud.fr
  # Tier 4 domains
  ecom-data.marionnaud.fr
  ecom-data.marionnaud.at
  ecom-data.marionnaud.ch
  ecom-data.marionnaud.it
  ecom-data.marionnaud.hu
  ecom-data.marionnaud.cz
  jeux-concours.marionnaud.fr
  campaign.marionnaud.at
  campaign.marionnaud.ch
  campaign.marionnaud.it
  campaign.marionnaud.hu
  campaign.marionnaud.cz
  campaign.marionnaud.ro
  campaign.marionnaud.sk
  # .com domain
  www.marionnaud.com
)

echo "=== Discovered Subdomain HTTP Probe — $(date) ===" > "$OUTPUT"

for domain in "${DOMAINS[@]}"; do
  echo "" | tee -a "$OUTPUT"
  echo ">>> $domain" | tee -a "$OUTPUT"

  # Try HTTPS first
  echo "--- HTTPS ---" >> "$OUTPUT"
  curl -sI -m 10 -L "https://$domain" 2>&1 >> "$OUTPUT"

  # If HTTPS fails, try HTTP
  https_code=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "https://$domain")
  if [ "$https_code" = "000" ]; then
    echo "--- HTTP (HTTPS failed) ---" >> "$OUTPUT"
    curl -sI -m 10 -L "http://$domain" 2>&1 >> "$OUTPUT"
  fi

  # Check robots.txt
  robots_code=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "https://$domain/robots.txt")
  if [ "$robots_code" = "200" ]; then
    echo "--- robots.txt ---" >> "$OUTPUT"
    curl -s -m 10 "https://$domain/robots.txt" >> "$OUTPUT"
  fi

  echo "Status: HTTPS=$https_code" | tee -a "$OUTPUT"
  sleep 0.5
done

echo ""
echo "Results saved to $OUTPUT"
