#!/bin/bash

export ORIGIN_URL=`git config --get remote.origin.url`
if [ -z "$ORIGIN_URL" ]; then
  echo "Move into the github project root to launch this script."
  exit;
fi
echo "Current repo url is: $ORIGIN_URL"
if [[ "$ORIGIN_URL" == *"open-sudo"* ]]; then
  echo "You CANNOT apply these changes to unvme331"
  exit;
fi

export GITHUB_BASE_URL=`dirname $ORIGIN_URL`
export GITHUB_NAME=`basename $GITHUB_BASE_URL`

echo "GitHub name is: $GITHUB_NAME"

if [ -z $GITHUB_NAME ]
then
    echo "Could not extract github user name"
    exit;
fi
status_code=$(curl --write-out '%{http_code}' --silent --output /dev/null https://github.com/$1)

if [[ "$status_code" -ne 200 ]] ; then
  echo "https://github.com/$1 returns status code: $status_code. I was expecting 200"
  exit 0
fi

echo "https://github.com/${GITHUB_NAME} successfully validated"

export OCP_TOKEN=`oc whoami --show-token`

if [ -z "$OCP_TOKEN" ]
then
    echo "No OpenShift token found. You might not be logged in."
    exit;
fi

echo "OCP Token found"

export CLUSTER_NAME=$(oc get infrastructure cluster -o=jsonpath="{.status.infrastructureName}"  |  rev | cut -c7- | rev)

if [ -z "$CLUSTER_NAME" ]
then
      echo "Cluster name could not be determined. You might not be logged in."
      exit;
fi
echo "Cluster name found: $CLUSTER_NAME"

export REGION=$(rosa describe cluster -c ${CLUSTER_NAME} --output json | jq -r .region.id)
if [ -z "$REGION" ]
then
      echo "Region could not be determined. You might not be logged in."
      exit;
fi

echo "Region found: $REGION"
export OIDC_ENDPOINT=$(oc get authentication.config.openshift.io cluster -o json | jq -r .spec.serviceAccountIssuer | sed  's|^https://||')
if [ -z "$OIDC_ENDPOINT" ]
then
      echo "OIDC Endpoint could not be determined. You might not be logged in."
      exit;
fi
echo "OIDC_ENDPOINT Found: $OIDC_ENDPOINT"
export AWS_ACCOUNT_ID=`aws sts get-caller-identity --query Account --output text`
if [ -z "$AWS_ACCOUNT_ID" ]
then
      echo "AWS Account ID could not be determined. You might not be logged in."
      exit;
fi

echo "AWS Account ID found: $AWS_ACCOUNT_ID"

export current=`git config --get remote.origin.url`
echo "Current repo url is: $current"
if [[ "$current" == *"open-sudo"* ]]; then
  echo "You CANNOT apply these changes to unvme331"
fi

find . -type f -not -path '*/\.git/*' -exec sed -i "s|unvme331|${GITHUB_NAME}|g" {} +
find . -type f -not -path '*/\.git/*' -exec sed -i "s|393387318561|${AWS_ACCOUNT_ID}|g" {} +
find . -type f -not -path '*/\.git/*' -exec sed -i "s|rh-oidc.s3.us-east-1.amazonaws.com/21blpv0rs8gquqa2p05rc9b9pbi2qif8|${OIDC_ENDPOINT}|g" {} +
find . -type f -not -path '*/\.git/*' -exec sed -i "s|us-east-2|${REGION}|g" {} +
find . -type f -not -path '*/\.git/*' -exec sed -i "s|gandolfrosa|${CLUSTER_NAME}|g" {} +


aws cloudformation create-stack --template-body file://cloudformation/rosa-cloudwatch-logging-role.yaml \
       --capabilities CAPABILITY_NAMED_IAM --parameters ParameterKey=OidcProvider,ParameterValue=$OIDC_ENDPOINT \
         ParameterKey=ClusterName,ParameterValue=${CLUSTER_NAME} --stack-name rosa-idp-cw-logs


aws cloudformation create-stack --template-body file://cloudformation/rosa-iam-external-secrets-role.yaml \
    --capabilities CAPABILITY_NAMED_IAM --parameters ParameterKey=OidcProvider,ParameterValue=$OIDC_ENDPOINT \
      ParameterKey=ClusterName,ParameterValue=${CLUSTER_NAME} --stack-name rosa-idp-iam-external-secrets

aws cloudformation create-stack --template-body file://cloudformation/rosa-ecr.yaml \
     --capabilities CAPABILITY_IAM  --stack-name rosa-idp-ecr

aws cloudformation create-stack --template-body file://cloudformation/rosa-cloudwatch-metrics-credentials.yaml \
     --capabilities CAPABILITY_NAMED_IAM  --stack-name rosa-idp-cw-metrics-credentials


aws cloudformation create-stack --template-body file://cloudformation/rosa-rds-inventory-credentials.yaml \
     --capabilities CAPABILITY_NAMED_IAM  --stack-name rosa-idp-rds-inventory-credentials
  
aws cloudformation create-stack --template-body file://cloudformation/rosa-rds-shared-instance-credentials.yaml \
     --capabilities CAPABILITY_NAMED_IAM  --stack-name rosa-idp-rds-shared-instance-credentials
  

aws cloudformation create-stack --template-body file://cloudformation/rosa-iam-external-secrets-rds-role.yaml \
    --capabilities CAPABILITY_NAMED_IAM --parameters ParameterKey=OidcProvider,ParameterValue=$OIDC_ENDPOINT \
      ParameterKey=ClusterName,ParameterValue=${CLUSTER_NAME} --stack-name rosa-idp-iam-external-secrets-rds


