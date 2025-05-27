#!/bin/bash

set -e

# Configuration
AWS_REGION=${AWS_REGION:-"us-east-1"}
ENVIRONMENT=${ENVIRONMENT:-"dev"}
PROJECT_NAME="bitcoin-address-matcher"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed and configured
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        error "Terraform is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured properly."
        exit 1
    fi
    
    success "All prerequisites are met."
}

# Deploy infrastructure with Terraform
deploy_infrastructure() {
    log "Deploying infrastructure with Terraform..."
    
    terraform init
    terraform plan -var="aws_region=$AWS_REGION" -var="environment=$ENVIRONMENT"
    
    read -p "Do you want to apply the Terraform plan? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform apply -var="aws_region=$AWS_REGION" -var="environment=$ENVIRONMENT" -auto-approve
        success "Infrastructure deployed successfully."
    else
        warning "Terraform apply cancelled."
        exit 0
    fi
}

# Build and push Docker image
build_and_push_image() {
    log "Building and pushing Docker image..."
    
    # Get ECR repository URL from Terraform output
    ECR_URL=$(terraform output -raw ecr_repository_url)
    
    if [ -z "$ECR_URL" ]; then
        error "Could not get ECR repository URL from Terraform output."
        exit 1
    fi
    
    log "ECR Repository URL: $ECR_URL"
    
    # Login to ECR
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL
    
    # Build the Docker image
    log "Building Docker image..."
    docker build -t $PROJECT_NAME .
    
    # Tag the image
    docker tag $PROJECT_NAME:latest $ECR_URL:latest
    
    # Push the image
    log "Pushing Docker image to ECR..."
    docker push $ECR_URL:latest
    
    success "Docker image pushed successfully."
}

# Update ECS service
update_ecs_service() {
    log "Updating ECS service..."
    
    CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
    SERVICE_NAME=$(terraform output -raw ecs_service_name)
    
    if [ -z "$CLUSTER_NAME" ] || [ -z "$SERVICE_NAME" ]; then
        error "Could not get ECS cluster or service name from Terraform output."
        exit 1
    fi
    
    # Force new deployment
    aws ecs update-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --force-new-deployment \
        --region $AWS_REGION
    
    success "ECS service update initiated."
}

# Upload sample addresses file to S3
upload_sample_addresses() {
    log "Would you like to upload a sample addresses file to S3?"
    read -p "Upload sample file? (y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        BUCKET_NAME=$(terraform output -raw s3_bucket_name)
        
        # Create a sample addresses file if it doesn't exist
        if [ ! -f "bitcoin_addresses.txt" ]; then
            log "Creating sample addresses file..."
            cat > bitcoin_addresses.txt << EOF
1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa
1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2
3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy
bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh
EOF
            success "Sample addresses file created."
        fi
        
        # Upload to S3
        aws s3 cp bitcoin_addresses.txt s3://$BUCKET_NAME/bitcoin_addresses.txt
        success "Addresses file uploaded to S3."
    fi
}

# Monitor deployment
monitor_deployment() {
    log "Monitoring ECS service deployment..."
    
    CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
    SERVICE_NAME=$(terraform output -raw ecs_service_name)
    
    log "Waiting for service to become stable..."
    aws ecs wait services-stable \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --region $AWS_REGION
    
    success "Service is now stable and running."
    
    # Show service status
    log "Current service status:"
    aws ecs describe-services \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --region $AWS_REGION \
        --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}' \
        --output table
}

# Show logs
show_logs() {
    log "Would you like to view the application logs?"
    read -p "View logs? (y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        LOG_GROUP="/ecs/$PROJECT_NAME-$ENVIRONMENT"
        
        log "Fetching recent logs from CloudWatch..."
        aws logs tail $LOG_GROUP --follow --region $AWS_REGION
    fi
}

# Main deployment flow
main() {
    log "Starting deployment of Bitcoin Address Matcher on ECS..."
    
    check_prerequisites
    deploy_infrastructure
    build_and_push_image
    update_ecs_service
    upload_sample_addresses
    monitor_deployment
    show_logs
    
    success "Deployment completed successfully!"
    
    echo
    log "Useful commands:"
    echo "  View logs: aws logs tail /ecs/$PROJECT_NAME-$ENVIRONMENT --follow --region $AWS_REGION"
    echo "  Scale service: aws ecs update-service --cluster $(terraform output -raw ecs_cluster_name) --service $(terraform output -raw ecs_service_name) --desired-count 2"
    echo "  Stop service: aws ecs update-service --cluster $(terraform output -raw ecs_cluster_name) --service $(terraform output -raw ecs_service_name) --desired-count 0"
}

# Handle script arguments
case "${1:-}" in
    "infrastructure")
        deploy_infrastructure
        ;;
    "build")
        build_and_push_image
        ;;
    "update")
        update_ecs_service
        ;;
    "logs")
        show_logs
        ;;
    "")
        main
        ;;
    *)
        echo "Usage: $0 [infrastructure|build|update|logs]"
        echo "  infrastructure: Deploy only the infrastructure"
        echo "  build:         Build and push Docker image only"
        echo "  update:        Update ECS service only"
        echo "  logs:          Show application logs"
        echo "  (no args):     Full deployment"
        exit 1
        ;;
esac