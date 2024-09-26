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


PORT=8000
# Docker image parameters
DOCKER_IMAGE_NAME="fastapiserver"
DOCKER_IMAGE_TAG="latest"

# App service plan parameters
ASP_NAME="fastapigasp"

# Web app parameters
WEB_APP_NAME="fastapiwa"


# Container registry parameters
ACR_NAME="fastapigacr"


######################
# LOGIN

echo "Logging into Azure"
az login

echo "Setting default subscription: $SUBSCRIPTION_ID"
az account set \
    --subscription $SUBSCRIPTION_ID

#####################
# DEPLOYMENT

# echo "Creating resource group: $RG_NAME"
# az group create \
#     --name $RG_NAME \
#     --location $RG_LOCATION


# echo "Creating Azure container registry: $ACR_NAME"
# az acr create \
#     --name $ACR_NAME \
#     --resource-group $RG_NAME \
#     --sku Basic \
#     --admin-enabled true 

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

# echo "Creating app service plan: $ASP_NAME"
# az appservice plan create \
#     --name $ASP_NAME \
#     --resource-group $RG_NAME \
#     --sku B1 \
#     --is-linux \
#     --location $RG_LOCATION

# echo "Creating web app: $WEB_APP_NAME"
# az webapp create \
#     --resource-group $RG_NAME \
#     --plan $ASP_NAME \
#     --name $WEB_APP_NAME \
#     --deployment-container-image-name $ACR_NAME.azurecr.io/$DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG

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
    --settings WEBSITES_PORT=$PORT

echo "Enabling access to logs generated from inside the container"
az webapp log config \
    --name $WEB_APP_NAME \
    --resource-group $RG_NAME \
    --docker-container-logging filesystem

echo "Setting environment to production"
az webapp config appsettings set \
    --resource-group $RG_NAME \
    --name $WEB_APP_NAME \
    --settings ENV=Production

az webapp restart --name $WEB_APP_NAME --resource-group $RG_NAME

