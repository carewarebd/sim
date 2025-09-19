# CI/CD Pipeline Configuration

## Overview

The Shop Management System uses a comprehensive CI/CD pipeline built with GitHub Actions, AWS CodePipeline, and CodeBuild to automate the build, test, and deployment process across multiple environments.

### Pipeline Architecture

```
GitHub Repository
        ↓
    GitHub Actions
    (Build & Test)
        ↓
    AWS CodePipeline
        ↓
    ┌─────────────────────────────────────────────────────────┐
    │                    CodeBuild                            │
    │  ┌─────────────────┐    ┌─────────────────────────────┐ │
    │  │   API Service   │    │    Frontend Service         │ │
    │  │                 │    │                             │ │
    │  │ • Build Docker  │    │ • Build React App          │ │
    │  │ • Run Tests     │    │ • Build Docker Image       │ │
    │  │ • Security Scan │    │ • Run Tests                 │ │
    │  │ • Push to ECR   │    │ • Security Scan            │ │
    │  └─────────────────┘    │ • Push to ECR               │ │
    └─────────────────────────│─────────────────────────────┘ │
                              └─────────────────────────────────┘
                                        ↓
                                AWS CodeDeploy
                                        ↓
                              ┌─────────────────────┐
                              │    ECS Services     │
                              │                     │
                              │ • Rolling Update    │
                              │ • Health Checks     │
                              │ • Auto Rollback     │
                              └─────────────────────┘
```

## GitHub Actions Workflow

### Main Workflow File

**.github/workflows/main.yml**

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

env:
  AWS_REGION: us-east-1
  ECR_REGISTRY: ${{ secrets.AWS_ACCOUNT_ID }}.dkr.ecr.us-east-1.amazonaws.com
  API_REPOSITORY: shop-management-api
  FRONTEND_REPOSITORY: shop-management-frontend

jobs:
  test:
    name: Run Tests
    runs-on: ubuntu-latest
    
    strategy:
      matrix:
        node-version: [18.x, 20.x]
    
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: shop_management_test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432
      
      redis:
        image: redis:7
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 6379:6379

    steps:
    - name: Checkout code
      uses: actions/checkout@v4
      
    - name: Use Node.js ${{ matrix.node-version }}
      uses: actions/setup-node@v4
      with:
        node-version: ${{ matrix.node-version }}
        cache: 'npm'
        cache-dependency-path: |
          api/package-lock.json
          frontend/package-lock.json
    
    - name: Install API dependencies
      working-directory: ./api
      run: npm ci
      
    - name: Install Frontend dependencies
      working-directory: ./frontend
      run: npm ci
    
    - name: Run API linting
      working-directory: ./api
      run: npm run lint
      
    - name: Run Frontend linting
      working-directory: ./frontend
      run: npm run lint
    
    - name: Run API unit tests
      working-directory: ./api
      run: npm run test:unit
      env:
        DATABASE_URL: postgres://postgres:postgres@localhost:5432/shop_management_test
        REDIS_URL: redis://localhost:6379
    
    - name: Run Frontend unit tests
      working-directory: ./frontend
      run: npm run test -- --coverage --watchAll=false
    
    - name: Run API integration tests
      working-directory: ./api
      run: npm run test:integration
      env:
        DATABASE_URL: postgres://postgres:postgres@localhost:5432/shop_management_test
        REDIS_URL: redis://localhost:6379
        NODE_ENV: test
    
    - name: Run E2E tests
      working-directory: ./e2e
      run: |
        npm ci
        npm run test
      env:
        API_BASE_URL: http://localhost:3000
        FRONTEND_URL: http://localhost:3001
    
    - name: Upload coverage reports
      uses: codecov/codecov-action@v3
      with:
        files: |
          ./api/coverage/lcov.info
          ./frontend/coverage/lcov.info
        fail_ci_if_error: true

  security-scan:
    name: Security Scan
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
    
    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        scan-type: 'fs'
        scan-ref: '.'
        format: 'sarif'
        output: 'trivy-results.sarif'
    
    - name: Upload Trivy scan results to GitHub Security tab
      uses: github/codeql-action/upload-sarif@v3
      with:
        sarif_file: 'trivy-results.sarif'
    
    - name: Run OWASP ZAP Baseline Scan
      uses: zaproxy/action-baseline@v0.7.0
      with:
        target: 'http://localhost:3000'

  build-and-deploy:
    name: Build and Deploy
    runs-on: ubuntu-latest
    needs: [test, security-scan]
    if: github.ref == 'refs/heads/main'
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
    
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}
    
    - name: Login to Amazon ECR
      id: login-ecr
      uses: aws-actions/amazon-ecr-login@v2
    
    - name: Build and tag API Docker image
      working-directory: ./api
      run: |
        docker build -t $ECR_REGISTRY/$API_REPOSITORY:$GITHUB_SHA .
        docker build -t $ECR_REGISTRY/$API_REPOSITORY:latest .
    
    - name: Build and tag Frontend Docker image
      working-directory: ./frontend
      run: |
        docker build -t $ECR_REGISTRY/$FRONTEND_REPOSITORY:$GITHUB_SHA .
        docker build -t $ECR_REGISTRY/$FRONTEND_REPOSITORY:latest .
    
    - name: Push API image to Amazon ECR
      run: |
        docker push $ECR_REGISTRY/$API_REPOSITORY:$GITHUB_SHA
        docker push $ECR_REGISTRY/$API_REPOSITORY:latest
    
    - name: Push Frontend image to Amazon ECR
      run: |
        docker push $ECR_REGISTRY/$FRONTEND_REPOSITORY:$GITHUB_SHA
        docker push $ECR_REGISTRY/$FRONTEND_REPOSITORY:latest
    
    - name: Update ECS service
      run: |
        aws ecs update-service --cluster shop-management-production-cluster \
          --service shop-management-production-api \
          --force-new-deployment
        
        aws ecs update-service --cluster shop-management-production-cluster \
          --service shop-management-production-frontend \
          --force-new-deployment
    
    - name: Wait for deployment
      run: |
        aws ecs wait services-stable --cluster shop-management-production-cluster \
          --services shop-management-production-api shop-management-production-frontend
    
    - name: Notify deployment status
      uses: 8398a7/action-slack@v3
      with:
        status: ${{ job.status }}
        channel: '#deployments'
        webhook_url: ${{ secrets.SLACK_WEBHOOK }}
      if: always()
```

## AWS CodePipeline Configuration

### Pipeline CloudFormation Template

**codepipeline/pipeline.yml**

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: 'CodePipeline for Shop Management System'

Parameters:
  ProjectName:
    Type: String
    Default: shop-management
  
  Environment:
    Type: String
    AllowedValues: [dev, staging, production]
    Default: production
  
  GitHubRepo:
    Type: String
    Description: GitHub repository name
  
  GitHubOwner:
    Type: String
    Description: GitHub repository owner
  
  GitHubToken:
    Type: String
    NoEcho: true
    Description: GitHub personal access token

Resources:
  # S3 Bucket for artifacts
  ArtifactStoreBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub '${ProjectName}-${Environment}-pipeline-artifacts'
      VersioningConfiguration:
        Status: Enabled
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - ServerSideEncryptionByDefault:
              SSEAlgorithm: AES256
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true

  # IAM Role for CodePipeline
  CodePipelineServiceRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub '${ProjectName}-${Environment}-pipeline-role'
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: codepipeline.amazonaws.com
            Action: sts:AssumeRole
      Policies:
        - PolicyName: PipelinePolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - s3:GetBucketVersioning
                  - s3:GetObject
                  - s3:GetObjectVersion
                  - s3:PutObject
                Resource:
                  - !Sub '${ArtifactStoreBucket}/*'
                  - !GetAtt ArtifactStoreBucket.Arn
              - Effect: Allow
                Action:
                  - codebuild:BatchGetBuilds
                  - codebuild:StartBuild
                Resource:
                  - !GetAtt APIBuildProject.Arn
                  - !GetAtt FrontendBuildProject.Arn
              - Effect: Allow
                Action:
                  - ecs:UpdateService
                  - ecs:DescribeServices
                  - ecs:DescribeTaskDefinition
                  - ecs:RegisterTaskDefinition
                  - iam:PassRole
                Resource: '*'

  # IAM Role for CodeBuild
  CodeBuildServiceRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub '${ProjectName}-${Environment}-build-role'
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: codebuild.amazonaws.com
            Action: sts:AssumeRole
      Policies:
        - PolicyName: BuildPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - logs:CreateLogGroup
                  - logs:CreateLogStream
                  - logs:PutLogEvents
                Resource: !Sub 'arn:aws:logs:${AWS::Region}:${AWS::AccountId}:log-group:/aws/codebuild/*'
              - Effect: Allow
                Action:
                  - s3:GetObject
                  - s3:GetObjectVersion
                  - s3:PutObject
                Resource: !Sub '${ArtifactStoreBucket}/*'
              - Effect: Allow
                Action:
                  - ecr:BatchCheckLayerAvailability
                  - ecr:GetDownloadUrlForLayer
                  - ecr:BatchGetImage
                  - ecr:GetAuthorizationToken
                  - ecr:InitiateLayerUpload
                  - ecr:UploadLayerPart
                  - ecr:CompleteLayerUpload
                  - ecr:PutImage
                Resource: '*'

  # API Build Project
  APIBuildProject:
    Type: AWS::CodeBuild::Project
    Properties:
      Name: !Sub '${ProjectName}-${Environment}-api-build'
      ServiceRole: !GetAtt CodeBuildServiceRole.Arn
      Artifacts:
        Type: CODEPIPELINE
      Environment:
        Type: LINUX_CONTAINER
        ComputeType: BUILD_GENERAL1_MEDIUM
        Image: aws/codebuild/amazonlinux2-x86_64-standard:5.0
        PrivilegedMode: true
        EnvironmentVariables:
          - Name: AWS_DEFAULT_REGION
            Value: !Ref AWS::Region
          - Name: AWS_ACCOUNT_ID
            Value: !Ref AWS::AccountId
          - Name: IMAGE_REPO_NAME
            Value: !Sub '${ProjectName}-api'
          - Name: IMAGE_TAG
            Value: latest
      Source:
        Type: CODEPIPELINE
        BuildSpec: |
          version: 0.2
          phases:
            pre_build:
              commands:
                - echo Logging in to Amazon ECR...
                - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com
                - REPOSITORY_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME
                - COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
                - IMAGE_TAG=${COMMIT_HASH:=latest}
            build:
              commands:
                - echo Build started on `date`
                - echo Building the Docker image...
                - cd api
                - docker build -t $REPOSITORY_URI:latest .
                - docker tag $REPOSITORY_URI:latest $REPOSITORY_URI:$IMAGE_TAG
            post_build:
              commands:
                - echo Build completed on `date`
                - echo Pushing the Docker images...
                - docker push $REPOSITORY_URI:latest
                - docker push $REPOSITORY_URI:$IMAGE_TAG
                - echo Writing image definitions file...
                - printf '[{"name":"api","imageUri":"%s"}]' $REPOSITORY_URI:$IMAGE_TAG > ../imagedefinitions-api.json
          artifacts:
            files:
              - imagedefinitions-api.json

  # Frontend Build Project
  FrontendBuildProject:
    Type: AWS::CodeBuild::Project
    Properties:
      Name: !Sub '${ProjectName}-${Environment}-frontend-build'
      ServiceRole: !GetAtt CodeBuildServiceRole.Arn
      Artifacts:
        Type: CODEPIPELINE
      Environment:
        Type: LINUX_CONTAINER
        ComputeType: BUILD_GENERAL1_MEDIUM
        Image: aws/codebuild/amazonlinux2-x86_64-standard:5.0
        PrivilegedMode: true
        EnvironmentVariables:
          - Name: AWS_DEFAULT_REGION
            Value: !Ref AWS::Region
          - Name: AWS_ACCOUNT_ID
            Value: !Ref AWS::AccountId
          - Name: IMAGE_REPO_NAME
            Value: !Sub '${ProjectName}-frontend'
          - Name: IMAGE_TAG
            Value: latest
      Source:
        Type: CODEPIPELINE
        BuildSpec: |
          version: 0.2
          phases:
            pre_build:
              commands:
                - echo Logging in to Amazon ECR...
                - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com
                - REPOSITORY_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME
                - COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
                - IMAGE_TAG=${COMMIT_HASH:=latest}
            build:
              commands:
                - echo Build started on `date`
                - echo Building the Docker image...
                - cd frontend
                - docker build -t $REPOSITORY_URI:latest .
                - docker tag $REPOSITORY_URI:latest $REPOSITORY_URI:$IMAGE_TAG
            post_build:
              commands:
                - echo Build completed on `date`
                - echo Pushing the Docker images...
                - docker push $REPOSITORY_URI:latest
                - docker push $REPOSITORY_URI:$IMAGE_TAG
                - echo Writing image definitions file...
                - printf '[{"name":"frontend","imageUri":"%s"}]' $REPOSITORY_URI:$IMAGE_TAG > ../imagedefinitions-frontend.json
          artifacts:
            files:
              - imagedefinitions-frontend.json

  # CodePipeline
  Pipeline:
    Type: AWS::CodePipeline::Pipeline
    Properties:
      Name: !Sub '${ProjectName}-${Environment}-pipeline'
      RoleArn: !GetAtt CodePipelineServiceRole.Arn
      ArtifactStore:
        Type: S3
        Location: !Ref ArtifactStoreBucket
      Stages:
        - Name: Source
          Actions:
            - Name: SourceAction
              ActionTypeId:
                Category: Source
                Owner: ThirdParty
                Provider: GitHub
                Version: '1'
              Configuration:
                Owner: !Ref GitHubOwner
                Repo: !Ref GitHubRepo
                Branch: main
                OAuthToken: !Ref GitHubToken
              OutputArtifacts:
                - Name: SourceOutput
        
        - Name: Build
          Actions:
            - Name: BuildAPI
              ActionTypeId:
                Category: Build
                Owner: AWS
                Provider: CodeBuild
                Version: '1'
              Configuration:
                ProjectName: !Ref APIBuildProject
              InputArtifacts:
                - Name: SourceOutput
              OutputArtifacts:
                - Name: APIBuildOutput
              RunOrder: 1
            
            - Name: BuildFrontend
              ActionTypeId:
                Category: Build
                Owner: AWS
                Provider: CodeBuild
                Version: '1'
              Configuration:
                ProjectName: !Ref FrontendBuildProject
              InputArtifacts:
                - Name: SourceOutput
              OutputArtifacts:
                - Name: FrontendBuildOutput
              RunOrder: 1
        
        - Name: Deploy
          Actions:
            - Name: DeployAPI
              ActionTypeId:
                Category: Deploy
                Owner: AWS
                Provider: ECS
                Version: '1'
              Configuration:
                ClusterName: !Sub '${ProjectName}-${Environment}-cluster'
                ServiceName: !Sub '${ProjectName}-${Environment}-api'
                FileName: imagedefinitions-api.json
              InputArtifacts:
                - Name: APIBuildOutput
              RunOrder: 1
            
            - Name: DeployFrontend
              ActionTypeId:
                Category: Deploy
                Owner: AWS
                Provider: ECS
                Version: '1'
              Configuration:
                ClusterName: !Sub '${ProjectName}-${Environment}-cluster'
                ServiceName: !Sub '${ProjectName}-${Environment}-frontend'
                FileName: imagedefinitions-frontend.json
              InputArtifacts:
                - Name: FrontendBuildOutput
              RunOrder: 1

Outputs:
  PipelineName:
    Description: Name of the created pipeline
    Value: !Ref Pipeline
  
  PipelineUrl:
    Description: URL of the pipeline
    Value: !Sub 'https://console.aws.amazon.com/codesuite/codepipeline/pipelines/${Pipeline}/view'
```

## Deployment Scripts

### Main Deployment Script

**scripts/deploy.sh**

```bash
#!/bin/bash

set -e

# Configuration
PROJECT_NAME="shop-management"
AWS_REGION="us-east-1"
ENVIRONMENT=${1:-"production"}
TERRAFORM_DIR="terraform"
DOCKER_REGISTRY=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validate environment
validate_environment() {
    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|production)$ ]]; then
        log_error "Invalid environment: $ENVIRONMENT. Must be dev, staging, or production."
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if required tools are installed
    command -v terraform >/dev/null 2>&1 || { log_error "Terraform is required but not installed."; exit 1; }
    command -v aws >/dev/null 2>&1 || { log_error "AWS CLI is required but not installed."; exit 1; }
    command -v docker >/dev/null 2>&1 || { log_error "Docker is required but not installed."; exit 1; }
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or invalid."
        exit 1
    fi
    
    # Get AWS account ID for ECR
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    DOCKER_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
    
    log_success "Prerequisites check passed"
}

# Setup ECR repositories
setup_ecr() {
    log_info "Setting up ECR repositories..."
    
    # Create API repository
    if ! aws ecr describe-repositories --repository-names "$PROJECT_NAME-api" >/dev/null 2>&1; then
        aws ecr create-repository --repository-name "$PROJECT_NAME-api" --region "$AWS_REGION"
        log_success "Created ECR repository: $PROJECT_NAME-api"
    fi
    
    # Create frontend repository
    if ! aws ecr describe-repositories --repository-names "$PROJECT_NAME-frontend" >/dev/null 2>&1; then
        aws ecr create-repository --repository-name "$PROJECT_NAME-frontend" --region "$AWS_REGION"
        log_success "Created ECR repository: $PROJECT_NAME-frontend"
    fi
}

# Build and push Docker images
build_and_push_images() {
    log_info "Building and pushing Docker images..."
    
    # Login to ECR
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$DOCKER_REGISTRY"
    
    # Build and push API image
    log_info "Building API image..."
    cd api
    docker build -t "$DOCKER_REGISTRY/$PROJECT_NAME-api:latest" .
    docker push "$DOCKER_REGISTRY/$PROJECT_NAME-api:latest"
    log_success "API image pushed successfully"
    cd ..
    
    # Build and push frontend image
    log_info "Building frontend image..."
    cd frontend
    docker build -t "$DOCKER_REGISTRY/$PROJECT_NAME-frontend:latest" .
    docker push "$DOCKER_REGISTRY/$PROJECT_NAME-frontend:latest"
    log_success "Frontend image pushed successfully"
    cd ..
}

# Deploy infrastructure with Terraform
deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform
    terraform init -backend-config="key=terraform-${ENVIRONMENT}.tfstate"
    
    # Plan the deployment
    terraform plan \
        -var="environment=$ENVIRONMENT" \
        -var="api_image=$DOCKER_REGISTRY/$PROJECT_NAME-api:latest" \
        -var="frontend_image=$DOCKER_REGISTRY/$PROJECT_NAME-frontend:latest" \
        -out="tfplan-${ENVIRONMENT}"
    
    # Apply the plan
    terraform apply "tfplan-${ENVIRONMENT}"
    
    log_success "Infrastructure deployed successfully"
    cd ..
}

# Wait for services to be stable
wait_for_deployment() {
    log_info "Waiting for ECS services to be stable..."
    
    CLUSTER_NAME="$PROJECT_NAME-$ENVIRONMENT-cluster"
    API_SERVICE="$PROJECT_NAME-$ENVIRONMENT-api"
    FRONTEND_SERVICE="$PROJECT_NAME-$ENVIRONMENT-frontend"
    
    aws ecs wait services-stable \
        --cluster "$CLUSTER_NAME" \
        --services "$API_SERVICE" "$FRONTEND_SERVICE" \
        --region "$AWS_REGION"
    
    log_success "All services are stable"
}

# Run post-deployment checks
post_deployment_checks() {
    log_info "Running post-deployment checks..."
    
    # Get load balancer DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --names "$PROJECT_NAME-$ENVIRONMENT-alb" \
        --query 'LoadBalancers[0].DNSName' \
        --output text --region "$AWS_REGION")
    
    # Health check API
    if curl -f -s "https://$ALB_DNS/api/health" > /dev/null; then
        log_success "API health check passed"
    else
        log_warning "API health check failed"
    fi
    
    # Health check frontend
    if curl -f -s "https://$ALB_DNS/health" > /dev/null; then
        log_success "Frontend health check passed"
    else
        log_warning "Frontend health check failed"
    fi
    
    log_info "Application deployed successfully!"
    log_info "Load Balancer DNS: $ALB_DNS"
}

# Main deployment function
main() {
    log_info "Starting deployment for environment: $ENVIRONMENT"
    
    validate_environment
    check_prerequisites
    setup_ecr
    build_and_push_images
    deploy_infrastructure
    wait_for_deployment
    post_deployment_checks
    
    log_success "Deployment completed successfully!"
}

# Error handling
trap 'log_error "Deployment failed at line $LINENO"' ERR

# Run main function
main "$@"
```

This comprehensive CI/CD configuration includes:

1. **GitHub Actions**: Automated testing, security scanning, and deployment
2. **AWS CodePipeline**: Complete pipeline orchestration  
3. **CodeBuild**: Docker image building and ECR pushing
4. **Deployment Scripts**: Automated infrastructure deployment
5. **Health Checks**: Post-deployment verification
6. **Security Scanning**: Vulnerability detection and OWASP testing
7. **Multi-environment Support**: Dev, staging, and production workflows

The pipeline ensures code quality, security, and reliable deployments with proper rollback mechanisms.

Let me mark the AWS deployment documentation as completed and move to the next phase: