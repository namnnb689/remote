Databricks Infrastructure Setup with Terraform
Context:  
This document describes how to provision a complete Databricks infrastructure on Azure using Terraform, integrated with GitHub and Terraform Cloud (TFC).  
It follows the sequence of PRs (Procedure Requests) PR1 → PR13, with predicted continuation (PR14+) based on standard enterprise setup.
*** Table of Contents
Before Starting: Requirements + Address Planning
PR1: GitHub Team Creation
PR2: GitHub & Terraform Resources Creation
PR3: Entra ID (AAD) Provisioning for App Members
PR4: Landing Zone Setup – Subscription & Management Groups
PR5: Landing Zone Setup – Provider Registration
PR6: Landing Zone Setup – Service Principals (SPNs)
PR7: Network Setup – VNets, Subnets, NSGs
PR8: Landing Zone Setup – VWAN + Log Analytics Workspace
PR9: Terraform Workspace Variables Setup (TFC)
PR10: Databricks Resource Creation
PR11: Metastore & Baseline Configuration
### PR12: Databricks Cluster Provisioning

- Provision Databricks clusters via the Terraform module `plt-tf-databricks-cluster` to ensure consistent and reproducible cluster configuration across all environments (DEV, SIT, PROD).
- Configure cluster policies and enforce naming conventions to align with enterprise governance standards.
- Define cluster parameters such as:
  - **Node type**: Standard_DS3_v2 or higher
  - **Auto-scaling**: Enabled with defined min and max worker nodes
  - **Spark version**: Use the latest LTS-supported Databricks runtime
  - **Termination timeout**: Set to 30 minutes of inactivity to optimize cost
- Attach the clusters to the previously created **Unity Catalog metastore** and **schema**.
- Apply tags and metadata for resource tracking and cost management.
- Validate that clusters are provisioned successfully and can access:
  - ADLS Gen2 storage via the linked Key Vault secrets
  - The workspace and Unity Catalog metastore
- Ensure clusters are deployed in compliance with **Pega DevOps** operational policies for environment segregation and RBAC.

---

### PR13: Databricks ACLs & Security Controls

- Implement fine-grained **Access Control Lists (ACLs)** within Databricks for both users and groups.
- Assign workspace-level permissions to key user groups:
  - **ADMIN**: Full administrative access to workspace, clusters, jobs, and repos.
  - **DEVOPS_ENGINEER**: Manage infrastructure components, clusters, and configurations.
  - **DATA_ENGINEER**: Manage tables, jobs, and notebooks related to data pipelines.
  - **DATA_SCIENTIST / DATA_ANALYST**: Read/write access to designated schemas and compute clusters.
  - **SUPPORT_ENGINEER**: Read-only access for troubleshooting and monitoring.
- Configure **Unity Catalog permissions** at the catalog, schema, and table levels:
  - Catalog Owner: ADMIN
  - Schema Owner: DATA_ENGINEER
  - Data Access: Controlled by assigned groups via Terraform SCIM mappings.
- Enforce **Key Vault–backed secret scopes** for credentials and sensitive values.
- Apply **cluster-level ACLs** to restrict job execution and notebook access based on group role.
- Validate that all users inherit permissions according to the group structure defined in PR11.
- Establish monitoring hooks to ensure ACL integrity via Databricks REST API audit logs.

---

### ✅ Outcome

After completing PR12 and PR13:
- The Databricks infrastructure is ready with standardized cluster configurations.
- Access controls and governance policies are enforced across all environments.
- Security and compliance alignment is maintained with organizational DevOps and data governance frameworks.


Reference: Terraform Cloud Variables & Repo Structure
*** Folder Structure
terraform-databricks/
│
├── modules/
│   ├── network/
│   ├── databricks/
│   ├── monitoring/
│   └── security/
│
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── backend.tf
│   ├── prod/
│   └── staging/
│
├── versions.tf
├── providers.tf
└── README.md
*** Terraform Cloud Variable Mapping
| Variable | Description | Example | Sensitive |
|---------------------|---------------------|--------------|
| ARM_CLIENT_ID       | Azure SPN Client ID | UUID         |
| ARM_CLIENT_SECRET   | Azure SPN Secret    | Secret value | 
| ARM_TENANT_ID       | Azure Tenant        | UUID         | 
| ARM_SUBSCRIPTION_ID | Azure Subscription  | UUID         |
| TF_VAR_env          | Environment name    | dev          | 
| TF_VAR_region       | Azure region        | eastus2      |
*** PR4 → PR13 Detailed Steps
PR4: Landing Zone Setup – Azure Subscription & Management Group
Action: Create Azure subscription and resource groups using Terraform.
module "subscription_product_dev" {
  source = "../modules/subscription"
  subscription_name = "product-dev"
  management_group  = "mg-landingzone"
  location          = "eastus2"
}
***PR5: Azure Subscription Provider Registration
resource "azapi_resource_action" "register" {
  type        = "Microsoft.Resources/subscriptions@2021-01-01"
  action      = "register"
  name        = "Microsoft.Databricks"
}
***PR6: Setup SPNs (Service Principals)
module "spn_databricks_admin" {
  source = "../modules/spn"
  name   = "spn-databricks-admin"
  roles  = ["Contributor"]
}
***PR7: Network Setup
module "network" {
  source              = "../modules/network"
  vnet_name           = "vnet-dbx"
  address_space       = ["10.1.0.0/16"]
  private_subnet_cidr = ["10.1.1.0/24"]
}
***PR8: VWAN + LAW Setup
module "log_analytics" {
  source  = "../modules/monitoring"
  name    = "log-analytics-db"
  sku     = "PerGB2018"
}
***PR9: Terraform Cloud Workspace Variables Setup
Configure variables in Terraform Cloud workspace (organization: your-org, workspace: databricks-dev).
Variables include Azure credentials and environment settings.
***PR10: Databricks Resource Creation
module "databricks" {
  source                  = "../modules/databricks"
  workspace_name          = "dbx-dev"
  resource_group_name     = module.subscription_product_dev.rg_name
  location                = "eastus2"
  sku                     = "premium"
  enable_no_public_ip     = true
  custom_parameters = {
    no_public_ip         = true
    virtual_network_id   = module.network.vnet_id
    private_subnet_name  = module.network.private_subnet_name
  }
}
***PR11: Metastore Assignment & Baseline Configuration
resource "databricks_metastore" "uc" {
  name          = "metastore-dev"
  storage_root  = "abfss://metastore@storageaccount.dfs.core.windows.net/"
  region        = "eastus2"
}
***PR12: Databricks Cluster Provisioning
resource "databricks_cluster" "default" {
  cluster_name            = "default-dev"
  spark_version           = "13.3.x-scala2.12"
  node_type_id            = "Standard_DS3_v2"
  autotermination_minutes = 30
  num_workers             = 2
}
***PR13: Databricks ACLs & Security
resource "databricks_permissions" "workspace_admins" {
  access_control {
    group_name       = "grp-databricks-admins"
    permission_level = "CAN_MANAGE"
  }
}


