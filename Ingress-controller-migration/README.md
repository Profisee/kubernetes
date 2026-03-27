# Ingress Controller Migration (ingress-nginx -> F5 NGINX OSS)

Due to Kubernetes security decommissioning around `ingress-nginx`, Profisee is migrating to **F5 NGINX OSS (Open Source Software)** for ingress.  
Reference: [Ingress NGINX Retirement Notice](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/).

This folder provides migration assets for customers running:

- **Azure ARM deployments** (public AKS + public ingress), or
- **Private PaaS deployments** (load balancer with a private IP).

## Important Notes

- This procedure is intended for a **platform administrator**.
- Perform this during a **planned maintenance window**.
- Back up relevant configuration and deployment values before running.
- If your environment is custom, or you are not confident running this procedure, contact Profisee Support by submitting a ticket at **https://profisee.com/support** before proceeding.

## Support and Warranty Disclaimer

- Profisee support and warranty coverage applies to the Profisee application/container components as defined by your applicable agreement.
- While Profisee makes reasonable efforts to cover a wide range of deployment scenarios in these scripts, Profisee cannot be held liable for failures in customer infrastructure environments.
- Customer-owned and customer-managed infrastructure (including, without limitation, Kubernetes clusters, ingress controllers, DNS/CoreDNS, load balancers, cloud networking, identities, and security policies) remains the customer's responsibility.
- The migration and rollback scripts in this folder are provided **"as is"** and **without warranties of any kind**, whether express or implied, including implied warranties of merchantability, fitness for a particular purpose, title, and non-infringement.
- Profisee is not liable for infrastructure-level outages, misconfiguration, data loss, security events, or operational impacts resulting from use or modification of these scripts in customer-managed environments.
- Customers are responsible for validating changes in non-production first, maintaining backups and rollback plans, and obtaining internal approvals before production execution.

## What The Migration Script Does

The ingress controller swap itself typically takes about **2-5 minutes** in normal conditions (not including pre-checks, validation, or any environment-specific troubleshooting).

The migration flow is designed to:

1. Detect whether the current environment is public AKS ingress or private-IP ingress.
2. Uninstall existing `ingress-nginx`.
3. Install F5 NGINX OSS ingress.
4. Update the cluster CoreDNS custom entry to point to the active NGINX ingress service name.
5. Discover currently deployed Profisee values (including Purview values).
6. Re-deploy Profisee with those discovered values.
7. Restart the Profisee runtime/pod so the environment comes back on the new ingress path.

## Files In This Folder

- `1. Migrate from Ingress-Nginx to F5 Nginx.txt`: migration runbook/script steps.
- `2. Rollback from F5 Nginx to Ingress-Nginx.txt`: rollback runbook/script steps.

Use these scripts as administrative runbooks. For public AKS ingress, open your AKS cluster in Azure Portal, select **Connect**, launch **Cloud Shell** (Bash, not PowerShell), and run the script there after auto-login. For private PaaS, sign in to the jumpbox and run the script from the jumpbox. Depending on whether Bash is available or not, the scripts might have to be converted to PowerShell equivalents.
