#!/bin/bash

if [[ "$#" -eq 0 ]]; then
  echo "Invalid parameters"
  echo "Command to deploy client code: deployment.sh -c --stack-name <CloudFormation stack name>"
  echo "Command to deploy server code: deployment.sh -s --stack-name <CloudFormation stack name>"
  echo "Command to deploy server & client code: deployment.sh -s -c --stack-name <CloudFormation stack name>"
  exit 1
fi

while [[ "$#" -gt 0 ]]; do
  case $1 in
  -s) server=1 ;;
  -c) client=1 ;;
  --stack-name)
    stackname=$2
    shift
    ;;
  *)
    echo "Unknown parameter passed: $1"
    exit 1
    ;;
  esac
  shift
done

if [[ -z "$stackname" ]]; then
  echo "Please provide CloudFormation stack name as parameter"
  echo "Note: Invoke script without parameters to know the list of script parameters"
  exit 1
fi

if [[ $server -eq 1 ]]; then
  echo "Server code is getting deployed"
  cd ../server || exit # stop execution if cd fails
  REGION=$(aws configure get region)

  # Ensure API Gateway CloudWatch Logs role is configured (one-time account setup)
  echo "Checking API Gateway CloudWatch Logs role configuration..."
  APIGW_ROLE=$(aws apigateway get-account --region "$REGION" --query 'cloudwatchRoleArn' --output text 2>/dev/null || echo "None")
  if [[ "$APIGW_ROLE" == "None" ]] || [[ -z "$APIGW_ROLE" ]]; then
    echo "API Gateway CloudWatch role not set. Configuring now..."
    ROLE_NAME=APIGatewayCloudWatchLogsRole
    
    # Create role if it doesn't exist
    if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
      echo "Creating IAM role $ROLE_NAME..."
      aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document '{
          "Version": "2012-10-17",
          "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "apigateway.amazonaws.com"},
            "Action": "sts:AssumeRole"
          }]
        }' >/dev/null
      
      echo "Attaching policy to role..."
      aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs
      
      # Wait for IAM propagation (can take up to 10 seconds)
      echo "Waiting for IAM role propagation..."
      sleep 10
    fi
    
    ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
    echo "Setting API Gateway account CloudWatch role to $ROLE_ARN..."
    
    # Retry update-account up to 3 times with backoff for IAM propagation
    RETRY_COUNT=0
    MAX_RETRIES=3
    until aws apigateway update-account \
      --patch-operations op=replace,path=/cloudwatchRoleArn,value="$ROLE_ARN" \
      --region "$REGION" >/dev/null 2>&1; do
      RETRY_COUNT=$((RETRY_COUNT + 1))
      if [[ $RETRY_COUNT -ge $MAX_RETRIES ]]; then
        echo "ERROR: Could not set API Gateway CloudWatch role after $MAX_RETRIES attempts."
        echo "IAM role may need more time to propagate. Wait 2-3 minutes and rerun."
        exit 1
      fi
      echo "Retry $RETRY_COUNT/$MAX_RETRIES: Waiting for IAM propagation (10s)..."
      sleep 10
    done
    
    echo "API Gateway CloudWatch role configured successfully."
  else
    echo "API Gateway CloudWatch role already configured."
  fi

  DEFAULT_SAM_S3_BUCKET=$(grep s3_bucket samconfig.toml | cut -d'=' -f2 | cut -d \" -f2)
  echo "aws s3 ls s3://$DEFAULT_SAM_S3_BUCKET"

  if ! aws s3 ls "s3://${DEFAULT_SAM_S3_BUCKET}"; then
    echo "S3 Bucket: $DEFAULT_SAM_S3_BUCKET specified in samconfig.toml is not readable.
      So creating a new S3 bucket and will update samconfig.toml with new bucket name."

    UUID=$(uuidgen | awk '{print tolower($0)}')
    SAM_S3_BUCKET=sam-bootstrap-bucket-$UUID
    # Create bucket in configured region; add LocationConstraint when not us-east-1
    if [[ "$REGION" == "us-east-1" ]]; then
      aws s3api create-bucket --bucket "$SAM_S3_BUCKET" --region "$REGION"
    else
      aws s3api create-bucket --bucket "$SAM_S3_BUCKET" --region "$REGION" \
        --create-bucket-configuration LocationConstraint="$REGION"
    fi
    if [[ $? -ne 0 ]]; then
      echo "Failed to create bootstrap bucket $SAM_S3_BUCKET in region $REGION"
      exit 1
    fi

    aws s3api put-bucket-encryption \
      --bucket "$SAM_S3_BUCKET" \
      --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}' || exit 1
    # Updating samconfig.toml with new bucket name
    ex -sc '%s/s3_bucket = .*/s3_bucket = \"'$SAM_S3_BUCKET'\"/|x' samconfig.toml
  fi

  echo "Validating server code using pylint"
  python3 -m pylint -E -d E0401 $(find . -iname "*.py" -not -path "./.aws-sam/*")
  if [[ $? -ne 0 ]]; then
    echo "****ERROR: Please fix above code errors and then rerun script!!****"
    exit 1
  fi

  sam build -t template.yaml --use-container
  sam deploy --config-file samconfig.toml --region="$REGION" --stack-name="$stackname"
  cd ../scripts || exit # stop execution if cd fails
fi

if [[ $client -eq 1 ]]; then
  echo "Client code is getting deployed"
  APP_SITE_BUCKET=$(aws cloudformation describe-stacks --stack-name "$stackname" --query "Stacks[0].Outputs[?OutputKey=='AppBucket'].OutputValue" --output text)
  APP_SITE_URL=$(aws cloudformation describe-stacks --stack-name "$stackname" --query "Stacks[0].Outputs[?OutputKey=='ApplicationSite'].OutputValue" --output text)
  APP_APIGATEWAYURL=$(aws cloudformation describe-stacks --stack-name "$stackname" --query "Stacks[0].Outputs[?OutputKey=='APIGatewayURL'].OutputValue" --output text)

  # Configuring application UI

  echo "aws s3 ls s3://${APP_SITE_BUCKET}"
  if ! aws s3 ls "s3://${APP_SITE_BUCKET}"; then
    echo "Error! S3 Bucket: $APP_SITE_BUCKET not readable"
    exit 1
  fi

  cd ../client/Application || exit # stop execution if cd fails

  echo "Configuring environment for App Client"

  cat <<EoF >./src/environments/environment.prod.ts
export const environment = {
  production: true,
  apiGatewayUrl: '$APP_APIGATEWAYURL'
};
EoF

  cat <<EoF >./src/environments/environment.ts
export const environment = {
  production: true,
  apiGatewayUrl: '$APP_APIGATEWAYURL'
};
EoF

  npm install && npm run build

  echo "aws s3 sync --delete --cache-control no-store dist s3://${APP_SITE_BUCKET}"
  if ! aws s3 sync --delete --cache-control no-store dist "s3://${APP_SITE_BUCKET}"; then
    exit 1
  fi

  echo "Completed configuring environment for App Client"

  echo "Application site URL: https://${APP_SITE_URL}"
fi
