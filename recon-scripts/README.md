# Marionnaud Recon Scripts

Run these scripts from a machine with unrestricted network access.
All scripts respect the program's rate limit of max 5 requests/sec.

## Prerequisites
- `curl`, `jq` installed
- Unrestricted outbound HTTPS access

## Usage

```bash
chmod +x *.sh
mkdir -p results

# Run in order:
./01-http-headers.sh          # HTTP headers for all Tier 1+2 domains
./02-sap-admin-paths.sh       # SAP Hybris admin console + path probing
./03-discovered-subdomains.sh # HTTP probe all DNS-discovered subdomains
./04-ct-logs.sh               # Certificate Transparency log enumeration
./05-occ-api-enum.sh          # OCC REST API v2 endpoint mapping
./06-waf-fingerprint.sh       # Akamai WAF identification + behavior
```

## Results
All output goes to `results/` directory.

## Important
- Register on the target sites with your @intigriti.me email
- Stay within program scope
- Max 5 requests/sec
- Do not test DoS/brute force
