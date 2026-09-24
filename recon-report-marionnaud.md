# AS Watson / Marionnaud — Deep Dive Recon Report

**Date:** 2026-09-24
**Program:** AS Watson / Marionnaud on Intigriti
**Scope:** Marionnaud brand — 8 European countries
**Methods:** Passive DNS enumeration, reverse DNS, OSINT, search-cache robots.txt, technology profiling
**Limitation:** Cloud environment egress proxy blocked direct HTTP to marionnaud.* — DNS and OSINT only

---

## 1. ATTACK SURFACE OVERVIEW

### Infrastructure Map

```
                         Internet
                            |
               +------------+------------+
               |                         |
      +--------v--------+     +---------v---------+
      |  Akamai CDN/WAF |     | Non-Akamai Infra  |
      |  23.217.77.130  |     | (see below)       |
      +--------+--------+     +---------+---------+
               |                         |
    +----------+----------+    +---------+---------+-----------+
    |          |          |    |         |         |           |
  www.*    api.*    media.*   CRM      UAT     BDES      Legacy
  app.*  campaign.*          83.98.   83.98.  193.240.  213.152.
                             213.201  213.204 185.11    23.72/75
```

### Domain Count by Tier

| Tier | Count | Type | Bounty Range |
|------|-------|------|-------------|
| Tier 1 | ~20 | Main e-commerce (FR/AT/CH/IT) | $100–$8,500 |
| Tier 2 | ~20 | E-commerce (HU/CZ/RO/SK) | $100–$5,500 |
| Tier 4 | ~17 | Marketing, supplier portals | $50–$2,000 |
| Tier 5 | 12+ | Wildcard domains | $10–$500 |

---

## 2. TECHNOLOGY STACK (CONFIRMED)

| Component | Technology | Confidence |
|-----------|-----------|------------|
| E-commerce Platform | **SAP Commerce Cloud (Hybris)** | Confirmed (program description + press) |
| Frontend | **SAP Spartacus / Angular SPA** | Confirmed (press: April 2024 migration) |
| API Layer | **OCC REST API v2** (`/occ/v2/`) | Confirmed (Spartacus standard) |
| CDN/WAF | **Akamai** (likely Kona / App & API Protector) | Confirmed (DNS + rDNS) |
| SSL | DigiCert OV certificates | High confidence |
| Analytics | Google Analytics, Contentsquare, GTM | High confidence |
| Email (FR) | On-premises (Alionis, 77.72.92.5) | Confirmed (MX records) |
| Email (others) | Microsoft 365 | Confirmed (MX records) |
| Email marketing | Emarsys (SAP-owned) | Confirmed (SPF records) |
| Affiliate | Awin | Confirmed (robots.txt `/?awin*`) |
| O365 Tenant | `asweu.onmicrosoft.com` (AS Watson EU) | Confirmed (DKIM CNAME) |
| Security Training | KnowBe4 | Confirmed (TXT record on .it) |
| Document Signing | DocuSign | Confirmed (TXT record on .it) |
| Email Auth Monitoring | OnDMARC (Red Sift) | Confirmed (DMARC rua records) |
| IAST | iast.it platform (via extranet.ch) | Confirmed (CNAME) |

---

## 3. HIGH-PRIORITY FINDINGS

### FINDING 1: Missing DMARC on marionnaud.fr (REPORTABLE)
- **Severity:** Medium
- **Impact:** Email spoofing from @marionnaud.fr — the primary French domain
- **Detail:** ALL other 7 TLDs have `DMARC p=reject` with OnDMARC monitoring. France alone has NO DMARC record.
- **SPF exists** (`-all` hardfail) but without DMARC, receivers won't enforce it consistently
- **Context:** marionnaud.fr is also the only domain still on on-premises mail (not M365) — suggests incomplete migration

### FINDING 2: No CAA Records on Any Domain
- **Severity:** Low–Medium
- **Impact:** Any Certificate Authority can issue certificates for all marionnaud.* domains
- **Recommendation:** Should restrict to DigiCert (their confirmed CA)

### FINDING 3: marionnaud.it Wildcard SPF (Softfail)
- **Severity:** Low–Medium
- **Impact:** ANY subdomain of marionnaud.it (even `phishing.marionnaud.it`) returns a wildcard TXT with SPF `~all` (softfail) authorizing Emarsys + Outlook
- **Detail:** Parent domain uses strict OnDMARC setup, but the wildcard undermines it for subdomains

---

## 4. HIGH-VALUE TARGETS (Needs HTTP Probing)

### Priority 1 — BDES Employee Data Endpoints
- `bdes-api.marionnaud.fr` → 193.240.185.11 (dedicated IP, no rDNS)
- `bdese.marionnaud.fr` → 193.240.185.11
- **BDES** = Base de Données Économiques, Sociales et Environnementales (French mandatory employee economic/social database)
- API endpoint for employee data — high-value PII target
- Separate infrastructure from everything else

### Priority 2 — UAT/Pre-Production Environments
- `uat.marionnaud.fr` → 83.98.213.204
- `uat.marionnaud.at` → 83.98.213.204 (same IP)
- No reverse DNS, dedicated infrastructure
- Pre-prod environments often have: weaker auth, debug enabled, test accounts, relaxed WAF

### Priority 3 — CRM Systems
- `crm.marionnaud.fr` → 83.98.213.201
- `crm.marionnaud.it` → 83.98.213.201
- `crm.marionnaud.at` → 83.98.213.201
- Same /24 as UAT — all three countries share one CRM deployment
- Customer PII repository

### Priority 4 — extranet.marionnaud.ch (IAST Platform)
- CNAME → `marionnaud.live.iast.it` (137.74.20.55, OVH)
- IAST = Interactive Application Security Testing platform
- May expose: security scan results, application internals, vulnerability data
- Third-party hosted on OVH

### Priority 5 — Legacy Infrastructure (213.152.23.x, AS8218/Zayo)
- `fs.marionnaud.fr` → 213.152.23.72 (possible ADFS — Active Directory Federation Services)
- `newsletter.marionnaud.fr` → 213.152.23.72
- `recrutement.marionnaud.fr` → 213.152.23.72
- `pro.marionnaud.fr` → 213.152.23.72
- `sftp.marionnaud.fr` → 213.152.23.75
- 4 services on one IP = vhost-based hosting (potential vhost confusion)
- Legacy ISP infrastructure, likely less maintained
- rDNS: `static.not.updated.as8218.eu` — confirms neglect

### Priority 6 — On-Premises French Infrastructure (Alionis 77.72.92.x)
- `static.marionnaud.fr` → 77.72.92.49
- `webmail.marionnaud.fr` → 86.64.60.250 (rDNS: mail.marionnaud.com)
- MX: 77.72.92.5 (mxtgate01.marionnaud.com)
- Dedicated Alionis network with gateway at 77.72.92.1 (gate-marionnaud.alionis.net)
- NOT behind Akamai — direct exposure

---

## 5. INFRASTRUCTURE GROUPS

| Group | IPs | Domains | Notes |
|-------|-----|---------|-------|
| **Akamai Main** | 23.217.77.130 | All www/api/app/media (28 domains) | Primary e-commerce, WAF-protected |
| **Akamai Campaign** | 23.217.76.206 | 7x campaign.*, jeux-concours.fr | Marketing sites |
| **Google** | 216.239.{32,34,36,38}.21 | 8x ecom-data.* | Analytics/dashboards |
| **Marionnaud CRM** | 83.98.213.201 | crm.marionnaud.fr/it/at | Centralized CRM, no rDNS |
| **Marionnaud UAT** | 83.98.213.204 | uat.marionnaud.fr/at | Pre-production, no rDNS |
| **BDES Dedicated** | 193.240.185.11 | bdes-api/bdese.marionnaud.fr | Employee data, no rDNS |
| **Legacy Zayo** | 213.152.23.72–75 | newsletter/recrutement/pro/fs/sftp.fr | Old infra, multiple vhosts |
| **Alionis** | 77.72.92.x | static.fr, MX gateway | French on-prem hosting |
| **OVH** | 137.74.20.55 | extranet.marionnaud.ch | IAST testing platform |
| **Webmail** | 86.64.60.250 | webmail.marionnaud.fr | SFR network, rDNS: mail.marionnaud.com |

---

## 6. DISCOVERED SUBDOMAINS (Beyond Program Listing)

### New / Unlisted Subdomains Found via DNS Brute-Force

| Subdomain | IP | Infrastructure | Interest |
|-----------|-----|---------------|----------|
| `uat.marionnaud.fr` | 83.98.213.204 | Dedicated | HIGH — pre-prod |
| `uat.marionnaud.at` | 83.98.213.204 | Dedicated | HIGH — pre-prod |
| `crm.marionnaud.fr` | 83.98.213.201 | Dedicated | HIGH — customer data |
| `crm.marionnaud.it` | 83.98.213.201 | Dedicated | HIGH — customer data |
| `crm.marionnaud.at` | 83.98.213.201 | Dedicated | HIGH — customer data |
| `fs.marionnaud.fr` | 213.152.23.72 | Legacy Zayo | HIGH — possible ADFS |
| `sftp.marionnaud.fr` | 213.152.23.75 | Legacy Zayo | MEDIUM — file transfer |
| `newsletter.marionnaud.fr` | 213.152.23.72 | Legacy Zayo | MEDIUM |
| `recrutement.marionnaud.fr` | 213.152.23.72 | Legacy Zayo | MEDIUM — recruitment portal |
| `pro.marionnaud.fr` | 213.152.23.72 | Legacy Zayo | MEDIUM — pro/B2B portal |
| `static.marionnaud.fr` | 77.72.92.49 | Alionis | LOW — static content |
| `webmail.marionnaud.fr` | 86.64.60.250 | SFR | MEDIUM — webmail portal |
| `www.marionnaud.com` | 23.217.77.130 | Akamai | LOW — likely redirect |

### Subdomains That Do NOT Resolve
staging, dev, test, preprod, admin, cms, bo, portal, intranet, mail, vpn, m, mobile, shop, store, cdn, assets, img, login, sso, auth, checkout, payment, tracking, analytics

---

## 7. ROBOTS.TXT ANALYSIS (Cached)

### www.marionnaud.fr
```
Disallow: /?awin*          → Awin affiliate tracking
Disallow: /crm/            → CRM endpoint (HIGH interest)
Disallow: /cart*            → Shopping cart
Disallow: /checkout         → Checkout flow
Disallow: /my-account       → User account area
Disallow: /login            → Login page
Disallow: /bcm/             → Unknown module (HIGH interest)
Disallow: /test             → Test pages (HIGH interest)
Disallow: /c//p/*           → Double-slash URL pattern (potential misconfig)
Disallow: /search*          → Search functionality
Sitemap: /sitemap.xml
Sitemap: /v/nc/sitemap/sitemap.xml
```

### www.marionnaud.ch
```
Disallow: /cart*
Disallow: /checkout*
Disallow: /my-account*
Disallow: /login*
Disallow: /register*
Disallow: /search?
Disallow: /search/
Disallow: /a/               → Unknown path (unique to CH — HIGH interest)
Disallow: ?lgw_code=        → LGW parameter
Disallow: ?LGWCODE=         → Same param different case (case sensitivity bug?)
Sitemap: /sitemap.xml
Sitemap: /de/v/nc/sitemap/sitemap.xml
Sitemap: /fr/v/nc/sitemap/sitemap.xml
```

### Notable Observations
- `/crm/` and `/bcm/` on FR — internal system paths exposed
- `/test` on FR — test environment exists
- `/c//p/*` double-slash — potential URL normalization issue
- `/a/` on CH only — unknown purpose, unique path
- `?lgw_code=` vs `?LGWCODE=` on CH — case inconsistency in parameters

---

## 8. EMAIL SECURITY POSTURE

| Domain | MX | SPF | DMARC | DKIM | Rating |
|--------|-----|-----|-------|------|--------|
| marionnaud.fr | On-prem (Alionis) | `-all` (hard) | **MISSING** | Unknown | WEAK |
| marionnaud.at | M365 | OnDMARC | `p=reject` | O365 | STRONG |
| marionnaud.ch | M365 | OnDMARC | `p=reject` | O365 | STRONG |
| marionnaud.it | M365 | OnDMARC | `p=reject` | O365 | STRONG |
| marionnaud.hu | M365 | OnDMARC | `p=reject` | O365 | STRONG |
| marionnaud.cz | M365 | OnDMARC | `p=reject` | O365 | STRONG |
| marionnaud.ro | M365 | OnDMARC | `p=reject` | O365 | STRONG |
| marionnaud.sk | M365 | OnDMARC | `p=reject` | O365 | STRONG |

**France stands out** as the only country with on-premises email AND missing DMARC — a clear gap in the migration.

---

## 9. SAP COMMERCE CLOUD / HYBRIS — TEST MATRIX

### Critical Admin Paths (test on all www.* domains)

| Path | Description | Expected | Risk |
|------|-------------|----------|------|
| `/hac/` | Hybris Administration Console | Should be 403 | CRITICAL if exposed |
| `/backoffice/` | Hybris Backoffice | Should be 403 | CRITICAL if exposed |
| `/smartedit/` | CMS Editor | Should be 403 | CRITICAL if exposed |
| `/hmc/` | Management Console (legacy) | Should be 404 | HIGH if exposed |
| `/solrfacetsearch/` | Solr search admin | Should be 403 | HIGH if exposed |
| `/virtualjdbc/` | Virtual JDBC console | Should be 403 | CRITICAL if exposed |
| `/monitoring/` | System monitoring | Should be 403 | HIGH if exposed |
| `/console/` | Console access | Should be 403 | HIGH if exposed |

### OCC API Endpoints (PRIMARY API SURFACE)

| Path | Description | Priority |
|------|-------------|----------|
| `/occ/v2/` | API root | HIGH |
| `/occ/v2/swagger-ui/index.html` | Swagger docs (full API schema) | HIGH |
| `/occ/v2/{site}/users/` | User data API | HIGH |
| `/occ/v2/{site}/orders/` | Order data API | HIGH |
| `/occ/v2/{site}/carts/` | Cart API | HIGH |
| `/occ/v2/{site}/products/` | Product catalog API | MEDIUM |
| `/occ/v2/{site}/cms/` | CMS content API | MEDIUM |
| `/rest/` | Legacy REST endpoints | MEDIUM |

### Common Web Paths

| Path | Purpose |
|------|---------|
| `/.env` | Environment file leak |
| `/.git/HEAD` | Git repo exposure |
| `/.well-known/security.txt` | Security contact info |
| `/.well-known/openid-configuration` | OIDC discovery |
| `/crm/` | CRM integration (from robots.txt) |
| `/bcm/` | Unknown internal module (from robots.txt) |
| `/test` | Test pages (from robots.txt) |

---

## 10. THIRD-PARTY SERVICES MAP

| Service | Purpose | Domain/Evidence |
|---------|---------|----------------|
| Akamai | CDN + WAF + DNS | All main domains |
| SAP Commerce Cloud | E-commerce platform | Program desc + press |
| Microsoft 365 | Email + productivity | MX records (7 countries) |
| Emarsys | Email marketing | SPF records |
| Contentsquare | Digital analytics | Tech profiles |
| Google Analytics/GTM | Web analytics | Tech profiles |
| Amazon SES | Transactional email | Tech profiles |
| Awin | Affiliate network | robots.txt |
| KnowBe4 | Security awareness | TXT record (.it) |
| DocuSign | Document signing | TXT record (.it) |
| OnDMARC (Red Sift) | Email auth monitoring | DMARC records |
| iast.it | Security testing | CNAME (extranet.ch) |
| Alionis | French hosting | MX + IP ownership |
| DigiCert | SSL certificates | OSINT |

---

## 11. RECOMMENDED NEXT STEPS

### Immediate — Requires Network Access Update

To continue recon from this environment, add these domains to the egress allowlist (environment settings > Edit > Network access):

**Priority domains to unblock:**
1. `*.marionnaud.fr` — primary target + legacy infra
2. `*.marionnaud.at`, `*.marionnaud.ch`, `*.marionnaud.it` — Tier 1
3. `83.98.213.201`, `83.98.213.204` — CRM + UAT (direct IP)
4. `193.240.185.11` — BDES employee data
5. `crt.sh` — certificate transparency logs

### Testing Priorities (from any environment)

1. **HTTP probe all discovered subdomains** — headers, login pages, error pages, tech fingerprinting
2. **Test SAP admin consoles** (`/hac/`, `/backoffice/`, `/smartedit/`) on all 8 www.* domains
3. **Map OCC API** — check for Swagger exposure, test IDOR on user/order/cart endpoints
4. **Probe BDES endpoints** — employee data API, authentication bypass
5. **Test UAT environments** — debug features, test accounts, relaxed security
6. **Probe CRM systems** — authentication, data exposure
7. **Investigate legacy infra** — fs/sftp/newsletter/recrutement/pro on .fr
8. **Certificate Transparency** — run crt.sh queries locally for full subdomain enumeration
9. **Test robots.txt paths** — `/crm/`, `/bcm/`, `/test`, `/a/` (CH), `/c//p/*` double-slash
10. **Email spoofing PoC** — demonstrate marionnaud.fr DMARC gap impact

### Local Commands for CT Log Enumeration
```bash
for tld in fr at ch it hu cz ro sk com de es paris; do
  echo "=== marionnaud.$tld ==="
  curl -s "https://crt.sh/?q=%25.marionnaud.$tld&output=json" | \
    jq -r '.[].common_name, .[].name_value' | sort -u
  sleep 2
done
```
