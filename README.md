# Restaurant API Infrastructure

This repository contains the Terraform configuration for the Restaurant API infrastructure. It sets up a complete Azure environment including Function App, Cosmos DB, Key Vault, and Application Gateway for secure access.

## Project Overview

The Restaurant API is a simple system that manages a list of restaurants and their properties such as address, cuisine style, vegetarian options, opening hours, and delivery availability. The API allows users to query restaurants using various criteria and returns recommendations based on current time and user preferences.

## Architecture

The infrastructure includes:

- **Azure Function App**: Hosts the Restaurant API functions
- **Cosmos DB**: NoSQL database for storing restaurant data
- **Key Vault**: Secure storage for secrets and certificates
- **Application Gateway**: Secure entry point with WAF protection
- **Log Analytics**: Centralized logging and monitoring

## API Endpoints

- **Restaurant Recommendations**: `/api/restaurant-recommend` - Get restaurant recommendations based on query parameters
- **Admin Operations**: `/api/restaurants/admin` - Admin endpoint for managing restaurant data
- **Health Check**: `/api/health` - Service health monitoring endpoint

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) (v1.0.0+)
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) (v2.30.0+)
- Azure subscription
- Azure Storage Account for Terraform state (already configured)

## Setup

1. Clone this repository:
   ```bash
   git clone https://github.com/shaharst-tr/veronis-assignment-api
   cd restaurant-api-infrastructure
   ```

2. Create a `terraform.tfvars` file based on the example:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

3. Edit the `terraform.tfvars` file with your specific values.

4. Login to Azure:
   ```bash
   az login
   ```

5. Initialize Terraform:
   ```bash
   terraform init
   ```

6. Review the execution plan:
   ```bash
   terraform plan
   ```

7. Apply the configuration:
   ```bash
   terraform apply
   ```

## Testing the API

### Testing the Health Check Endpoint

```bash
curl -k https://your-gateway-fqdn.northeurope.cloudapp.azure.com/api/health
```

### Testing the Restaurant Recommendation API

```bash
# Basic test without parameters
curl -k https://your-gateway-fqdn.northeurope.cloudapp.azure.com/api/restaurant-recommend

# With query parameters
curl -k "https://your-gateway-fqdn.northeurope.cloudapp.azure.com/api/restaurant-recommend?style=Italian&vegetarian=true"
```

### Using the Admin API

The admin API requires authentication with an API key stored in Key Vault.

```bash
# Get your admin API key from Key Vault
ADMIN_KEY=$(az keyvault secret show --name "admin-api-key" --vault-name "your-key-vault-name" --query "value" --output tsv)

# Add a new restaurant
curl -k -X POST \
  -H "Content-Type: application/json" \
  -H "x-admin-key: $ADMIN_KEY" \
  -d '{
    "action": "add",
    "restaurant": {
      "name": "La Bella Italia",
      "style": "Italian",
      "address": "123 Pasta Avenue, Milan District",
      "openHour": "11:00",
      "closeHour": "23:00", 
      "vegetarian": true,
      "deliveries": true,
      "priceRange": "$$"
    }
  }' \
  https://your-gateway-fqdn.northeurope.cloudapp.azure.com/api/restaurants/admin

# List all restaurants
curl -k -H "x-admin-key: $ADMIN_KEY" \
  https://your-gateway-fqdn.northeurope.cloudapp.azure.com/api/restaurants/admin?action=list
```

## Security Features

- **Web Application Firewall (WAF)**: Protects against common web vulnerabilities
- **HTTPS Enforcement**: All traffic is encrypted
- **Key Vault Integration**: Securely stores and manages sensitive credentials
- **Managed Identities**: Uses Azure managed identities for service authentication
- **Network Security Groups**: Controls traffic flow between components

## Infrastructure Components

### Function App

The Function App hosts the API code and is secured with a system-assigned managed identity. It has access to Key Vault secrets and Cosmos DB data.

### Cosmos DB

Cosmos DB provides a scalable NoSQL database for storing restaurant information. The database uses `/style` as the partition key for efficient querying.

### Key Vault

Key Vault securely stores:
- Cosmos DB connection details
- Admin API key
- SSL certificate for Application Gateway
- Storage connection strings

### Application Gateway

Application Gateway provides:
- SSL termination
- WAF protection
- Path-based routing
- Health monitoring
- HTTP to HTTPS redirection

## Terraform Modules

### Function App Module
Provisions the Azure Function App that hosts the Restaurant API.

### Cosmos DB Module
Sets up the Cosmos DB account, database, and container for storing restaurant data.

### Key Vault Module
Creates a Key Vault for storing secrets and certificates securely.

### Networking Module
Configures the Application Gateway with WAF protection, providing secure access to the API.

## Troubleshooting

### Common Issues

1. **SSL Certificate Warnings**: The development environment uses a self-signed certificate. In production, will be replace with a trusted certificate.

2. **401 Unauthorized Errors**: Ensure you're using the correct admin API key. Check Key Vault for the current value.

3. **Application Gateway Health Probe Failures**: Verify that your function app is returning a 200 OK status from the health endpoint.

4. **CORS Issues**: If integrating with a web frontend, you may need to configure CORS settings in your Function App.

### Viewing Logs

- **Function App Logs**: Available in the Log Analytics workspace
- **Application Gateway Logs**: Review `ApplicationGatewayAccessLog` in Log Analytics
- **WAF Logs**: Check `ApplicationGatewayFirewallLog` for security events

## Cleanup

To destroy the infrastructure:

```bash
terraform destroy
```

Note: This will delete all resources. Make sure to backup any important data before running this command.