#!/bin/bash
set -vx


# ARO cluster name
#resourcePrefix="<azure-resources-name-prefix>"
resourcePrefix="aro-openshit-dev-cac-001"
#aroDomain="${resourcePrefix,,}"
aroDomain="xyz"
#aroClusterServicePrincipalDisplayName="${resourcePrefix}-aro-sp-${RANDOM}"
aroClusterServicePrincipalDisplayName="${resourcePrefix}-sp"
pullSecret=$(cat /Users/alirezarahmani/Repo/aro-azapi-terraform/pull-secret.txt)
# Name and location of the resource group for the Azure Red Hat OpenShift (ARO) cluster
aroResourceGroupName="${resourcePrefix}-RG"
location="canadacentral"

# Subscription id, subscription name, and tenant id of the current subscription
subscriptionId=$(az account show --query id --output tsv)
subscriptionName=$(az account show --query name --output tsv)
tenantId=$(az account show --query tenantId --output tsv)

# Register the necessary resource providers
az provider register --namespace 'Microsoft.RedHatOpenShift' --wait
az provider register --namespace 'Microsoft.Compute' --wait
az provider register --namespace 'Microsoft.Storage' --wait
az provider register --namespace 'Microsoft.Authorization' --wait

# Check if the resource group already exists
echo "Checking if [$aroResourceGroupName] resource group actually exists in the [$subscriptionName] subscription..."

az group show --name $aroResourceGroupName &>/dev/null

if [[ $? != 0 ]]; then
  echo "No [$aroResourceGroupName] resource group actually exists in the [$subscriptionName] subscription"
  echo "Creating [$aroResourceGroupName] resource group in the [$subscriptionName] subscription..."

  # Create the resource group
  az group create --name $aroResourceGroupName --location $location 1>/dev/null

  if [[ $? == 0 ]]; then
    echo "[$aroResourceGroupName] resource group successfully created in the [$subscriptionName] subscription"
  else
    echo "Failed to create [$aroResourceGroupName] resource group in the [$subscriptionName] subscription"
    exit
  fi
else
  echo "[$aroResourceGroupName] resource group already exists in the [$subscriptionName] subscription"
fi

# Create the service principal for the Azure Red Hat OpenShift (ARO) cluster
echo "Creating service principal with [$aroClusterServicePrincipalDisplayName] display name in the [$tenantId] tenant..."
az ad sp create-for-rbac --name $aroClusterServicePrincipalDisplayName > app-service-principal.json

aroClusterServicePrincipalClientId=$(jq -r '.appId' app-service-principal.json)
aroClusterServicePrincipalClientSecret=$(jq -r '.password' app-service-principal.json)
aroClusterServicePrincipalObjectId=$(az ad sp show --id $aroClusterServicePrincipalClientId | jq -r '.id')

# Assign the User Access Administrator role to the new service principal with resource group scope
roleName='User Access Administrator'
az role assignment create \
  --role "$roleName" \
  --assignee-object-id $aroClusterServicePrincipalObjectId \
  --resource-group $aroResourceGroupName \
  --assignee-principal-type 'ServicePrincipal' >/dev/null

if [[ $? == 0 ]]; then
  echo "[$aroClusterServicePrincipalDisplayName] service principal successfully assigned [$roleName] with [$aroResourceGroupName] resource group scope"
else
  echo "Failed to assign [$roleName] role with [$aroResourceGroupName] resource group scope to the [$aroClusterServicePrincipalDisplayName] service principal"
  exit
fi

# Assign the Contributor role to the new service principal with resource group scope
roleName='Contributor'
az role assignment create \
  --role "$roleName" \
  --assignee-object-id $aroClusterServicePrincipalObjectId \
  --resource-group $aroResourceGroupName \
  --assignee-principal-type 'ServicePrincipal' >/dev/null

if [[ $? == 0 ]]; then
  echo "[$aroClusterServicePrincipalDisplayName] service principal successfully assigned [$roleName] with [$aroResourceGroupName] resource group scope"
else
  echo "Failed to assign [$roleName] role with [$aroResourceGroupName] resource group scope to the [$aroClusterServicePrincipalDisplayName] service principal"
  exit
fi

# Get the service principal object ID for the OpenShift resource provider
# aroResourceProviderServicePrincipalObjectId=$(az ad sp list --display-name "Azure Red Hat OpenShift RP" --query "[0].id" -o tsv) >> app-service-principal.json

#az ad sp list --display-name "Azure Red Hat OpenShift RP" --query "[0].{Azure_RedHat_OpenShift_RP_ObjectId:id}"  >> app-service-principal.json
aroResourceProviderServicePrincipalObjectId=$(az ad sp list --display-name "Azure Red Hat OpenShift RP" --query [0].id -o tsv)
rm -r app-service-principal.json

echo "\nImportant Note: Please ensure variables_secrets file is part of .gitignore file before pushing to repo" >> variables_secrets

echo "\n## Setting Variables  ##\n" > variables_secrets
echo "\n## following variables will be set in tfvars##\n" >> variables_secrets

echo "domain:$aroDomain" >> variables_secrets
echo "location:$location " >> variables_secrets
echo "resource_group_name:$aroResourceGroupName" >> variables_secrets
echo "resource_prefix:$resourcePrefix" >> variables_secrets
echo "virtual_network_address_space = " >> variables_secrets
echo "master_subnet_address_space = " >> variables_secrets
echo "worker_subnet_address_space = " >> variables_secrets

echo "\n## following variables will be set as sensitive terraform variables in Terraform Cloud Workspace level ##\n" >> variables_secrets

echo "aro_cluster_aad_sp_client_id:$aroClusterServicePrincipalClientId" >> variables_secrets
echo "aro_cluster_aad_sp_client_secret:$aroClusterServicePrincipalClientSecret" >> variables_secrets
echo "aro_cluster_aad_sp_object_id:$aroClusterServicePrincipalObjectId" >> variables_secrets
echo "aro_rp_aad_sp_object_id:$aroResourceProviderServicePrincipalObjectId" >> variables_secrets
echo "pull_secret:$pullSecret" >> variables_secrets

echo "\n## following variables will be set as sensitive env variables in Terraform Cloud Workspace level ##\n" >> variables_secrets

echo "ARM_CLIENT_ID:$aroClusterServicePrincipalClientId" >> variables_secrets
echo "ARM_CLIENT_SECRET:$aroClusterServicePrincipalClientSecret" >> variables_secrets
echo "ARM_SUBSCRIPTION_ID:$subscriptionId" >> variables_secrets
echo "ARM_TENANT_ID:$tenantId" >>  variables_secrets


echo "\n## following variables will be set in Github repository seetings ##\n" >> variables_secrets

echo "ARM_CLIENT_ID:$aroClusterServicePrincipalClientId" >> variables_secrets
echo "ARM_CLIENT_SECRET:$aroClusterServicePrincipalClientSecret" >> variables_secrets
echo "ARM_SUBSCRIPTION_ID: $subscriptionId " >> variables_secrets
echo "ARM_TENANT_ID: $tenantId " >>  variables_secrets