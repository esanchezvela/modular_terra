# Active Directory Linux Lab on Azure

> [!WARNING]
> **LAB USE ONLY - NOT PRODUCTION READY**
>
> This repository is a **lab exercise** intended for learning, testing, and experimentation.
> It is **not designed or validated for production use** and should not be considered a production reference architecture.

## Overview

This project uses **Terraform** and automated provisioning to deploy an **Active Directory lab environment in Microsoft Azure**.

The lab includes a Windows Server Active Directory Domain Controller and **8 Linux Active Directory client VMs** running:

- 🟠 **Ubuntu**
- 🔵 **AlmaLinux**
- 🔴 **Red Hat Enterprise Linux (RHEL)**
- 🟦 **Azure Linux 4**
- 🟢 **SUSE Linux Enterprise Server (SLES 15)**
- 🟢 **SUSE Linux Enterprise Server 16 (SLES 16)** - *Planned*
 
> [!NOTE]
> **SLES 16 is planned work and is not currently part of the deployed lab environment.**

The Linux VMs are automatically configured and enrolled into the Active Directory domain as part of the deployment.

The purpose of this project is to provide a repeatable environment for experimenting with **Linux integration with Active Directory**, infrastructure automation, and Azure networking.

---

## 🧪 Lab at a Glance

| Component | Description |
|---|---|
| Active Directory | Windows Server Domain Controller |
| Linux Clients | **8 VMs** |
| Linux Distributions | Ubuntu, AlmaLinux, RHEL, Azure Linux 4, SLES15 |
| Infrastructure | Microsoft Azure |
| Deployment | Terraform |
| Linux AD Integration | SSSD |
| Automation | PowerShell, Python, Bash |
| Secrets | Azure Key Vault |
| Connectivity | Azure networking and Private Endpoints |

---

## 🏗️ Architecture

```text
                         Microsoft Azure
                                │
                  ┌─────────────┴─────────────┐
                  │                           │
           Windows Server               Azure Services
           Domain Controller                  │
                  │                    ┌───────┴───────┐
                  │                    │               │
                  │                Key Vault        Storage
                  │
                  │
          Active Directory Domain
                  │
     ┌────────────┼────────────┬────────────┬────────────┐
     │            │            │            │            │
     ▼            ▼            ▼            ▼            ▼
  Ubuntu      AlmaLinux       RHEL     Azure Linux 4    SLES
     │            │            │            │            │
     └────────────┴────────────┴────────────┴────────────┘
                          │
                 Linux AD Clients

```

The environment is designed to provide a controlled sandbox for exploring Active Directory integration across multiple Linux distributions.

---

## 💻 Linux Active Directory Clients

The lab deploys **8 Linux virtual machines** across four distributions:

### 🟠 Ubuntu

Ubuntu-based virtual machines configured as Active Directory clients.

### 🔵 AlmaLinux

AlmaLinux virtual machines used to test Active Directory integration in an Enterprise Linux-compatible environment.

### 🔴 Red Hat Enterprise Linux

RHEL virtual machines configured for Active Directory integration.

### 🟦 Azure Linux 4

Azure Linux 4 virtual machines used to explore Active Directory integration on Microsoft's Linux distribution.

### 🟢 SUSE Linux Enterprise Server (SLES 15)
 
SUSE Linux Enterprise Server virtual machines configured as Active Directory clients.
Together, these systems provide a multi-distribution environment for experimenting with Linux authentication and identity integration.

---

## 🪟 Active Directory Domain Controller

A Windows Server VM is provisioned as the lab's **Active Directory Domain Controller**.

The automated deployment configures the infrastructure required by the Linux clients for domain integration.

The overall workflow is:

```text
Deploy Infrastructure
        │
        ▼
Configure Domain Controller
        │
        ▼
Initialize Active Directory
        │
        ▼
Deploy Linux Clients
        │
        ▼
Configure Linux AD Integration
        │
        ▼
Join Linux Clients to the Domain
```

---

## ☁️ Azure Infrastructure

The lab brings together several Azure infrastructure components.

### Networking

- Azure Virtual Network
- Subnets
- Network Security Groups
- NAT Gateway
- Private Endpoints

### Identity and Secrets

- Azure Key Vault
- Azure RBAC
- Managed identities

### Provisioning and Automation

- Terraform
- Azure VM Extensions
- PowerShell
- Python
- Bash

---

## 🛠️ Technology Stack

| Technology | Role in the Lab |
|---|---|
| Terraform | Infrastructure deployment |
| Active Directory Domain Services | Windows identity services |
| SSSD | Linux AD integration |
| PowerShell | Windows and AD automation |
| Python | Provisioning automation |
| Bash | Linux configuration |
| Azure Key Vault | Secret management |
| Azure Blob Storage | Deployment resources |
| Azure Private Link | Private connectivity |
| Azure RBAC | Azure authorization |
| Azure VM Extensions | VM bootstrap and configuration |

---

## 🎯 Lab Goals

This project provides a sandbox for experimenting with:

- Infrastructure as Code using Terraform
- Automated Active Directory deployment
- Linux integration with Active Directory
- SSSD-based identity integration
- Multi-distribution Linux domain enrollment
- Windows and Linux provisioning automation
- Azure Key Vault integration
- Azure RBAC
- Azure Private Endpoints
- Azure networking
- VM bootstrap automation
- Resource dependencies and deployment sequencing

The focus is **learning, testing, troubleshooting, and experimentation**, rather than production architecture.

---

## 🚀 Getting Started

### Prerequisites

Before deploying the lab, ensure you have:

1. [Terraform CLI](https://developer.hashicorp.com/terraform/downloads)
2. https://learn.microsoft.com/cli/azure/install-azure-cli
3. An Azure subscription with permissions to deploy the required resources

Authenticate to Azure:

```bash
az login
```

### Clone the Repository

```bash
git clone https://github.com/esanchezvela/modular_terra.git
cd modular_terra/ADlab
```

### Configure the Lab

Review and modify:

```text
variables.auto.tfvars.json
```

Set the appropriate values for your lab environment before deployment.

### Initialize Terraform

```bash
terraform init
```

### Review the Terraform Plan

```bash
terraform plan
```

Review the proposed resources and configuration before proceeding.

### Deploy the Lab

```bash
terraform apply --auto-approve
```

---

## 🔍 Implementation Highlights

### Automated AD Provisioning

The lab uses automation to provision the Windows Server infrastructure required for Active Directory.

### Automated Linux Domain Integration

The Linux systems are configured for Active Directory integration as part of the lab deployment.

The same overall concept can therefore be explored across:

```text
Ubuntu | AlmaLinux | RHEL | Azure Linux 4 | SLES
```

### Azure Private Connectivity

The environment incorporates private connectivity for Azure services used by the lab.

### Deployment Dependencies

The environment contains dependencies between infrastructure provisioning, Active Directory initialization, and Linux client configuration.

This makes the project useful for exploring how dependent infrastructure can be coordinated through Terraform and automated provisioning.

---

## 📂 Repository Structure

The Terraform configuration contains components for areas such as:

```text
ADlab/
│
├── Active Directory Domain Controller
├── Linux VM provisioning
├── Linux domain integration
│
├── Networking
│   ├── Virtual Network
│   ├── Network Security Groups
│   ├── NAT Gateway
│   └── Private Endpoints
│
├── Azure Key Vault
├── Azure Storage
├── Azure RBAC
├── VM Extensions
└── Deployment dependencies
```

---

## ⚠️ Production Readiness

> [!CAUTION]
> ## This project is NOT production ready.

This repository was created as a **technical lab and learning exercise**.

It is intended to make it easy to deploy an environment, experiment with Active Directory and Linux integration, troubleshoot problems, modify configurations, and tear everything down when finished.

Before adapting any part of this project for production, independently evaluate areas such as:

- Security architecture
- Identity and access controls
- Credential and secret lifecycle
- Network security
- High availability
- Backup and recovery
- Disaster recovery
- Monitoring and alerting
- Logging and auditing
- Patch management
- Configuration management
- Terraform state management
- Operational processes

Configuration choices in this repository should **not be interpreted as production recommendations or official Microsoft deployment guidance**.

---

## 🧑‍🔬 Intended Use

This repository is meant to be a **sandbox**.

Use it to:

- 🔬 Experiment
- 📚 Learn
- 🧪 Test
- 🔧 Troubleshoot
- 💥 Break things
- 🛠️ Fix them
- 🔁 Repeat

**If something breaks, that's part of the lab.**

---

## 📜 Disclaimer

This project is provided for **educational, testing, and demonstration purposes only**.

It is **not intended for production environments** and does not represent a complete production architecture.

**Use at your own risk.**
