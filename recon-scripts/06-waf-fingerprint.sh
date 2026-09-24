#!/bin/bash
# AS Watson / Marionnaud — WAF/Akamai Fingerprinting
# Identify WAF type, bot protection, and bypass opportunities
# Max 5 req/sec

OUTPUT="results/waf-fingerprint.txt"
mkdir -p results

SITES=(www.marionnaud.fr www.marionnaud.at www.marionnaud.it www.marionnaud.hu)

echo "=== WAF Fingerprinting — $(date) ===" > "$OUTPUT"

for site in "${SITES[@]}"; do
  echo ""
  echo "====== $site ======" | tee -a "$OUTPUT"

  # Normal request — capture full headers + cookies
  echo "--- Normal Request ---" >> "$OUTPUT"
  curl -s -D - -o /dev/null -m 10 "https://$site/" 2>&1 >> "$OUTPUT"
  echo "" >> "$OUTPUT"
  sleep 0.3

  # XSS test string — trigger WAF
  echo "--- WAF Trigger (XSS) ---" >> "$OUTPUT"
  curl -sI -m 10 "https://$site/?q=<script>alert(1)</script>" 2>&1 >> "$OUTPUT"
  echo "" >> "$OUTPUT"
  sleep 0.3

  # SQLi test string — trigger WAF
  echo "--- WAF Trigger (SQLi) ---" >> "$OUTPUT"
  curl -sI -m 10 "https://$site/?id=1'%20OR%201=1--" 2>&1 >> "$OUTPUT"
  echo "" >> "$OUTPUT"
  sleep 0.3

  # Path traversal — trigger WAF
  echo "--- WAF Trigger (Path Traversal) ---" >> "$OUTPUT"
  curl -sI -m 10 "https://$site/../../etc/passwd" 2>&1 >> "$OUTPUT"
  echo "" >> "$OUTPUT"
  sleep 0.3

  # 404 error page fingerprint
  echo "--- 404 Error Page ---" >> "$OUTPUT"
  curl -s -m 10 "https://$site/nonexistent-path-$(date +%s)" 2>&1 | head -50 >> "$OUTPUT"
  echo "" >> "$OUTPUT"
  sleep 0.3

  # Check for Akamai debug headers
  echo "--- Akamai Debug (Pragma: akamai-x-cache-on) ---" >> "$OUTPUT"
  curl -sI -m 10 -H "Pragma: akamai-x-cache-on, akamai-x-cache-remote-on, akamai-x-check-cacheable, akamai-x-get-cache-key, akamai-x-get-true-cache-key" "https://$site/" 2>&1 >> "$OUTPUT"
  echo "" >> "$OUTPUT"
  sleep 0.5
done

echo ""
echo "Results saved to $OUTPUT"
echo ""
echo "Look for:"
echo "  - _abck, bm_sz, ak_bmsc cookies = Akamai Bot Manager"
echo "  - AkamaiGHost in Server header"
echo "  - Reference ID in error pages = Akamai WAF block"
echo "  - X-Akamai-Transformed header"
