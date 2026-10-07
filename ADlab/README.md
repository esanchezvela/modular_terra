## Automated Hybrid Identity Lab (Azure ADLab)
A fully automated Active Directory (AD) infrastructure deployed on Microsoft Azure using Infrastructure as Code (IaC). This lab provisions an isolated network environment featuring a Windows Domain Controller and 7 Linux client machines seamlessly enrolled into the AD domain upon creation.
The entire architecture is designed with a Zero-Trust perspective, utilizing Private Endpoints, strict Azure RBAC, and secure Key Vault secret management so that sensitive domain credentials and backend orchestration never expose themselves to the public internet.
------------------------------
## 🏗️ Architecture Overview
The lab deploys a modular, secure network topology in Azure that consists of:

* Identity & Domain Services: A Windows Server VM provisioned and bootstrapped automatically as an Active Directory Domain Controller (controller_bootstrap-extension.tf).
* Linux Client Fleet: 7 Linux Virtual Machines automatically enrolled into the Active Directory domain during provisioning (linux_commands-extension.tf).
* Zero-Trust Networking:
* Private Endpoints: Isolated connectivity for Azure Key Vault and Azure Blob Storage (keyvault_private_connection.tf, blob-private-connection.tf), ensuring secrets and bootstrap scripts move strictly across the Microsoft backbone network.
   * Secure Egress: A NAT Gateway handles managed outbound internet connectivity for updates without opening unmanaged inbound vectors (nat-gw.tf).
   * Micro-segmentation: Granular Network Security Groups (NSGs) locking down traffic between the clients and the Domain Controller (nsg.tf).
* Security & Secret Management:
* Azure Key Vault: Centralized management of domain admin passwords and enrollment tokens (keyvault.tf).
   * Azure RBAC: Strict Identity and Access Management applied to both Windows and Linux infrastructures (windows-rbac.tf, linux-rbac.tf).

------------------------------
## 🛠️ Tech Stack & Tooling

* Infrastructure as Code (IaC): Terraform (utilizing modular local references, explicit time delays for sequential bootstrapping, and structured variables.auto.tfvars.json).
* Configuration Management & Bootstrapping: PowerShell (for Windows Active Directory Domain services deployment) and Python / Bash scripts (for automated Linux realm/SSSD orchestration).
* Cloud Provider: Microsoft Azure (Compute, Networking, Storage, Security).

------------------------------
## 📁 Repository Structure
------------------------------
## 🚀 Deployment## Prerequisites

   1. [Terraform CLI](https://developer.hashicorp.com/terraform/downloads) installed.
   2. [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed and authenticated (az login).
   3. An active Azure Subscription with permissions to create Resource Groups, Key Vaults, and Virtual Machines.

## Step-by-Step Execution

   1. Clone the Repository:
   
   git clone https://github.com
   cd modular_terra/ADlab
   
   2. Configure Variables:
   Modify variables.auto.tfvars.json or customize variables.tf to match your desired naming conventions, domain paths (e.g., corp.local), and regional deployment settings.
   3. Initialize Terraform:
   
   terraform init
   
   4. Review the Plan:
   Inspect the execution path to verify all 7 Linux clients, private endpoints, and extensions are mapped correctly.
   
   terraform plan
   
   5. Deploy the Infrastructure:
   
   terraform apply --auto-approve
   
   Note: Due to built-in dependencies (time_delay.tf), the Linux extensions will intentionally wait for the Active Directory Domain Controller VM extension to finish provisioning its forest before attempting domain enrollment.

------------------------------
## 🔒 Deep Dive: Enterprise Design Patterns Implemented
## 1. Sequential Automation via VM Extensions
Rather than requiring manual post-deployment tasks, this lab relies heavily on Azure Custom Script Extensions. The Windows Domain Controller uses PowerShell to spin up AD, configure DNS, and establish the domain forest. Once complete, the Linux nodes execute automated Python/Bash routines to download domain details, configure SSSD (systemd), and bind seamlessly.
## 2. Private Link Isolation
To mimic real-world secure landing zones, the Azure Storage Account holding provisioning scripts and the Azure Key Vault holding domain passwords have public network access entirely disabled. All communication is routed privately through dedicated network interface cards (NICs) inside your VNet.
## 3. Graceful Race-Condition Prevention
Active Directory takes time to configure. To prevent the 7 Linux clients from attempting to join a domain controller that isn't fully operational yet, the Terraform configuration leverages explicit dependency tracking and time-delay resources to pause execution until the identity provider is healthy.
