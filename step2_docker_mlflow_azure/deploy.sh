#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace # Uncomment for debugging

#####################
# PARAMETERS

# Azure parameters
SUBSCRIPTION_ID="860fcc66-98e7-4c95-b1ff-dc6290d9e5dc"

# Resource group parameters
RG_NAME="mlops_series"
RG_LOCATION="francecentral"


# SQL Server parameters
SQL_SERVER_NAME="mlflowtrackingsqlserver"
SQL_DATABASE_NAME="mlflowtrackingsqldb"
SQL_ADMIN_USER="mlflowtrackingsqladmin"
SQL_ADMIN_PASSWORD="Sabrine20242"

# Docker image parameters
DOCKER_IMAGE_NAME="mlflowserver"
DOCKER_IMAGE_TAG="latest"

# App service plan parameters
ASP_NAME="mlflowtrackingasp"

# Web app parameters
WEB_APP_NAME="mlflowtrackingwa"

# MLFlow settings
MLFLOW_HOST=0.0.0.0
MLFLOW_PORT=5000
MLFLOW_WORKERS=1

# Storage parameters
STORAGE_ACCOUNT_NAME="mlflowtrackingstorage2"
STORAGE_CONTAINER_NAME="mlflowexperiments2"

# Container registry parameters
ACR_NAME="mlflowtrackingacr"

# Database URI
BACKEND_STORE_URI="mssql+pyodbc://${SQL_ADMIN_USER}@${SQL_SERVER_NAME}:${SQL_ADMIN_PASSWORD}@${SQL_SERVER_NAME}.database.windows.net:1433/${SQL_DATABASE_NAME}?driver=ODBC+Driver+18+for+SQL+Server&encrypt=yes&trustServerCertificate=no"


######################
# LOGIN

echo "Logging into Azure"
az login

echo "Setting default subscription: $SUBSCRIPTION_ID"
az account set \
    --subscription $SUBSCRIPTION_ID

#####################
# DEPLOYMENT

echo "Creating resource group: $RG_NAME"
az group create \
    --name $RG_NAME \
    --location $RG_LOCATION

echo "Creating Azure SQL Server: $SQL_SERVER_NAME"
az sql server create \
    --name $SQL_SERVER_NAME \
    --resource-group $RG_NAME \
    --location $RG_LOCATION \
    --admin-user $SQL_ADMIN_USER \
    --admin-password $SQL_ADMIN_PASSWORD

echo "Creating Azure SQL Database: $SQL_DATABASE_NAME"
az sql db create \
    --resource-group $RG_NAME \
    --server $SQL_SERVER_NAME \
    --name $SQL_DATABASE_NAME \
    --service-objective S0

echo "Configuring firewall for Azure SQL Server"
az sql server firewall-rule create \
    --resource-group $RG_NAME \
    --server $SQL_SERVER_NAME \
    --name AllowAllAzureIPs \
    --start-ip-address 0.0.0.0 \
    --end-ip-address 0.0.0.0

echo "Creating storage account: $STORAGE_ACCOUNT_NAME"
az storage account create \
    --resource-group $RG_NAME \
    --location $RG_LOCATION \
    --name $STORAGE_ACCOUNT_NAME \
    --sku Standard_LRS

echo "Creating storage container for MLflow artifacts: $STORAGE_CONTAINER_NAME"
az storage container create \
    --name $STORAGE_CONTAINER_NAME \
    --account-name $STORAGE_ACCOUNT_NAME


echo "Retrive artifact, access key, connection string"
export STORAGE_ACCESS_KEY=$(az storage account keys list --resource-group $RG_NAME --account-name $STORAGE_ACCOUNT_NAME --query "[0].value" --output tsv)
export STORAGE_CONNECTION_STRING=`az storage account show-connection-string --resource-group $RG_NAME --name $STORAGE_ACCOUNT_NAME --output tsv`

echo "Generating SAS Token for storage container"
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    EXPIRY_DATE=$(date -v+3d +"%Y-%m-%dT%H:%M:%SZ")
else
    # Assume Linux
    EXPIRY_DATE=$(date -u -d "3 days" '+%Y-%m-%dT%H:%M:%SZ')
fi

SAS_TOKEN=$(az storage container generate-sas \
  --account-name $STORAGE_ACCOUNT_NAME \
  --name $STORAGE_CONTAINER_NAME \
  --permissions lrw \
  --expiry $EXPIRY_DATE \
  --output tsv \
  --account-key $STORAGE_ACCESS_KEY)

# Add the SAS token to the environment variable
export STORAGE_ARTIFACT_ROOT="https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$STORAGE_CONTAINER_NAME?$SAS_TOKEN"


echo "Creating Azure container registry: $ACR_NAME"
az acr create \
    --name $ACR_NAME \
    --resource-group $RG_NAME \
    --sku Basic \
    --admin-enabled true 

echo "Getting Azure container registry credentials: $ACR_NAME"
export ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query "username" --output tsv)
export ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query "passwords[0].value" --output tsv)

echo "Logging into Azure container registry"
docker login $ACR_NAME.azurecr.io \
    --username "$ACR_USERNAME" \
    --password "$ACR_PASSWORD"


echo "Pushing image to Azure container registry: $ACR_NAME"
docker tag $DOCKER_IMAGE_NAME $ACR_NAME.azurecr.io/$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG
docker push $ACR_NAME.azurecr.io/$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG

echo "Creating app service plan: $ASP_NAME"
az appservice plan create \
    --name $ASP_NAME \
    --resource-group $RG_NAME \
    --sku B1 \
    --is-linux \
    --location $RG_LOCATION

echo "Creating web app: $WEB_APP_NAME"
az webapp create \
    --resource-group $RG_NAME \
    --plan $ASP_NAME \
    --name $WEB_APP_NAME \
    --deployment-container-image-name $ACR_NAME.azurecr.io/$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG

echo "Configuring registry credentials in web app"
az webapp config container set \
    --name $WEB_APP_NAME \
    --resource-group $RG_NAME \
    --docker-custom-image-name $ACR_NAME.azurecr.io/$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG \
    --docker-registry-server-url https://$ACR_NAME.azurecr.io \
    --docker-registry-server-user $ACR_USERNAME \
    --docker-registry-server-password $ACR_PASSWORD \
    --enable-app-service-storage true

echo "Setting Azure container registry credentials"
az webapp config appsettings set \
    --resource-group $RG_NAME \
    --name $WEB_APP_NAME \
    --settings WEBSITES_PORT=$MLFLOW_PORT

echo "Enabling access to logs generated from inside the container"
az webapp log config \
    --name $WEB_APP_NAME \
    --resource-group $RG_NAME \
    --docker-container-logging filesystem

echo "Setting environment variables"
APP_SETTINGS=(
   AZURE_STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION_STRING
   MLFLOW_BACKEND_STORE_URI=$BACKEND_STORE_URI
   MLFLOW_SERVER_DEFAULT_ARTIFACT_ROOT=$STORAGE_ARTIFACT_ROOT
   MLFLOW_SERVER_WORKERS=$MLFLOW_WORKERS
   MLFLOW_SERVER_PORT=$MLFLOW_PORT
   MLFLOW_SERVER_HOST=$MLFLOW_HOST
)

for setting in "${APP_SETTINGS[@]}"; do
    az webapp config appsettings set \
    --resource-group $RG_NAME \
    --name $WEB_APP_NAME \
    --settings "$setting"
done

echo "Verify linked storage account: $STORAGE_ACCOUNT_NAME"
az webapp config storage-account list \
    --resource-group $RG_NAME \
    --name $WEB_APP_NAME



