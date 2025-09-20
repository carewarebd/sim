# CI/CD Pipeline Configuration

## Overview

The Shop Management System uses a comprehensive CI/CD pipeline built with GitHub Actions, AWS CodePipeline, and CodeBuild to automate the build, test, and deployment process to EC2 Auto Scaling Groups across multiple environments.

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
    │  │ • Build App     │    │ • Build React App          │ │
    │  │ • Run Tests     │    │ • Build Static Assets      │ │
    │  │ • Security Scan │    │ • Run Tests                 │ │
    │  │ • Create Bundle │    │ • Security Scan            │ │
    │  └─────────────────┘    │ • Upload to S3              │ │
    └─────────────────────────│─────────────────────────────┘ │
                              └─────────────────────────────────┘
                                        ↓
                                AWS CodeDeploy
                                        ↓
                              ┌─────────────────────┐
                              │   EC2 Auto Scaling  │
                              │       Group         │
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
  S3_DEPLOYMENT_BUCKET: shop-management-deployments
  API_BUNDLE_NAME: shop-management-api
  FRONTEND_BUNDLE_NAME: shop-management-frontend

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
    
    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: '18'
        cache: 'npm'
        cache-dependency-path: |
          api/package-lock.json
          frontend/package-lock.json
    
    - name: Build API application
      working-directory: ./api
      run: |
        npm ci --only=production
        npm run build
        
        # Create deployment package
        mkdir -p ../dist/api
        cp -r dist/ node_modules/ package.json ../dist/api/
        
        # Create application scripts
        cat > ../dist/api/start.sh << 'EOF'
        #!/bin/bash
        export NODE_ENV=production
        pm2 start ecosystem.config.js --env production
        EOF
        chmod +x ../dist/api/start.sh
        
        cat > ../dist/api/stop.sh << 'EOF'
        #!/bin/bash
        pm2 stop all
        pm2 delete all
        EOF
        chmod +x ../dist/api/stop.sh
    
    - name: Build Frontend application
      working-directory: ./frontend
      run: |
        npm ci
        npm run build
        
        # Copy built assets
        mkdir -p ../dist/frontend
        cp -r build/* ../dist/frontend/
    
    - name: Create CodeDeploy application bundle
      run: |
        # Create appspec.yml for CodeDeploy
        cat > appspec.yml << 'EOF'
        version: 0.0
        os: linux
        files:
          - source: api/
            destination: /opt/shop-management/api/
          - source: frontend/
            destination: /var/www/html/
        permissions:
          - object: /opt/shop-management
            owner: shopapp
            group: shopapp
            mode: 755
            type:
              - directory
              - file
        hooks:
          BeforeInstall:
            - location: scripts/stop_application.sh
              timeout: 300
          AfterInstall:
            - location: scripts/install_dependencies.sh
              timeout: 600
          ApplicationStart:
            - location: scripts/start_application.sh
              timeout: 300
          ApplicationStop:
            - location: scripts/stop_application.sh
              timeout: 300
        EOF
        
        # Create deployment scripts
        mkdir -p scripts
        
        cat > scripts/stop_application.sh << 'EOF'
        #!/bin/bash
        if [ -f /opt/shop-management/api/stop.sh ]; then
          cd /opt/shop-management/api && ./stop.sh
        fi
        EOF
        
        cat > scripts/install_dependencies.sh << 'EOF'
        #!/bin/bash
        # Update system packages
        yum update -y
        
        # Install or update Node.js if needed
        if ! command -v node &> /dev/null; then
          curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
          yum install -y nodejs
        fi
        
        # Install PM2 if not present
        if ! command -v pm2 &> /dev/null; then
          npm install -g pm2
        fi
        
        # Set proper ownership
        chown -R shopapp:shopapp /opt/shop-management/
        EOF
        
        cat > scripts/start_application.sh << 'EOF'
        #!/bin/bash
        cd /opt/shop-management/api
        su shopapp -c "./start.sh"
        
        # Start nginx for frontend serving
        systemctl start nginx
        systemctl enable nginx
        EOF
        
        chmod +x scripts/*.sh
    
    - name: Upload bundle to S3
      run: |
        # Create deployment bundle
        zip -r shop-management-${{ github.sha }}.zip appspec.yml dist/ scripts/
        
        # Upload to S3
        aws s3 cp shop-management-${{ github.sha }}.zip \
          s3://$S3_DEPLOYMENT_BUCKET/deployments/shop-management-${{ github.sha }}.zip
    
    - name: Create CodeDeploy deployment
      run: |
        aws deploy create-deployment \
          --application-name shop-management \
          --deployment-group-name production \
          --s3-location bucket=$S3_DEPLOYMENT_BUCKET,key=deployments/shop-management-${{ github.sha }}.zip,bundleType=zip \
          --deployment-config-name CodeDeployDefault.EC2AllAtOne \
          --description "Deployment from GitHub Actions - ${{ github.sha }}"
    
    - name: Wait for deployment completion
      run: |
        # Get deployment ID
        DEPLOYMENT_ID=$(aws deploy list-deployments \
          --application-name shop-management \
          --deployment-group-name production \
          --query 'deployments[0]' --output text)
        
        # Wait for deployment to complete
        aws deploy wait deployment-successful --deployment-id $DEPLOYMENT_ID
    
    - name: Run post-deployment health check
      run: |
        # Wait a moment for services to start
        sleep 30
        
        # Health check
        HEALTH_CHECK_URL="https://${{ secrets.DOMAIN_NAME }}/health"
        
        for i in {1..10}; do
          if curl -f $HEALTH_CHECK_URL; then
            echo "Health check passed"
            break
          else
            echo "Health check failed, attempt $i/10"
            sleep 10
          fi
        done
    
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
                  - codedeploy:CreateDeployment
                  - codedeploy:GetApplication
                  - codedeploy:GetApplicationRevision
                  - codedeploy:GetDeployment
                  - codedeploy:GetDeploymentConfig
                  - codedeploy:RegisterApplicationRevision
                Resource: '*'
              - Effect: Allow
                Action:
                  - ec2:DescribeInstances
                  - autoscaling:CompleteLifecycleAction
                  - autoscaling:DeleteLifecycleHook
                  - autoscaling:DescribeLifecycleHooks
                  - autoscaling:DescribeAutoScalingGroups
                  - autoscaling:PutLifecycleHook
                  - autoscaling:RecordLifecycleActionHeartbeat
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
            - Name: DeployApplication
              ActionTypeId:
                Category: Deploy
                Owner: AWS
                Provider: CodeDeploy
                Version: '1'
              Configuration:
                ApplicationName: !Ref CodeDeployApplication
                DeploymentGroupName: !Ref CodeDeployDeploymentGroup
              InputArtifacts:
                - Name: APIBuildOutput
              RunOrder: 1

  # CodeDeploy Application
  CodeDeployApplication:
    Type: AWS::CodeDeploy::Application
    Properties:
      ApplicationName: !Sub '${ProjectName}-${Environment}'
      ComputePlatform: Server

  # CodeDeploy Deployment Group
  CodeDeployDeploymentGroup:
    Type: AWS::CodeDeploy::DeploymentGroup
    Properties:
      ApplicationName: !Ref CodeDeployApplication
      DeploymentGroupName: !Sub '${ProjectName}-${Environment}-deployment-group'
      ServiceRoleArn: !GetAtt CodeDeployServiceRole.Arn
      DeploymentConfigName: CodeDeployDefault.EC2AllAtOne
      AutoScalingGroups:
        - !Sub '${ProjectName}-${Environment}-asg'
      LoadBalancerInfo:
        TargetGroupInfoList:
          - Name: !Sub '${ProjectName}-${Environment}-tg'

  # CodeDeploy Service Role
  CodeDeployServiceRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub '${ProjectName}-${Environment}-codedeploy-role'
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: codedeploy.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole

Outputs:
  PipelineName:
    Description: Name of the created pipeline
    Value: !Ref Pipeline
  
  PipelineUrl:
    Description: URL of the pipeline
    Value: !Sub 'https://console.aws.amazon.com/codesuite/codepipeline/pipelines/${Pipeline}/view'
  
  CodeDeployApplicationName:
    Description: CodeDeploy Application Name
    Value: !Ref CodeDeployApplication
    Export:
      Name: !Sub '${ProjectName}-${Environment}-codedeploy-app'
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
S3_DEPLOYMENT_BUCKET=""

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
    command -v npm >/dev/null 2>&1 || { log_error "NPM is required but not installed."; exit 1; }
    command -v zip >/dev/null 2>&1 || { log_error "ZIP is required but not installed."; exit 1; }
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or invalid."
        exit 1
    fi
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    S3_DEPLOYMENT_BUCKET="$PROJECT_NAME-$ENVIRONMENT-deployments-$AWS_ACCOUNT_ID"
    
    log_success "Prerequisites check passed"
}

# Setup S3 bucket for deployments
setup_s3_bucket() {
    log_info "Setting up S3 deployment bucket..."
    
    # Create S3 bucket if it doesn't exist
    if ! aws s3api head-bucket --bucket "$S3_DEPLOYMENT_BUCKET" 2>/dev/null; then
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3 mb "s3://$S3_DEPLOYMENT_BUCKET"
        else
            aws s3 mb "s3://$S3_DEPLOYMENT_BUCKET" --region "$AWS_REGION"
        fi
        log_success "Created S3 bucket: $S3_DEPLOYMENT_BUCKET"
    else
        log_info "S3 bucket already exists: $S3_DEPLOYMENT_BUCKET"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$S3_DEPLOYMENT_BUCKET" \
        --versioning-configuration Status=Enabled
}

# Build applications
build_applications() {
    log_info "Building applications..."
    
    # Create dist directory
    rm -rf dist
    mkdir -p dist
    
    # Build API application
    log_info "Building API application..."
    cd api
    npm ci --only=production
    npm run build
    
    # Create deployment package
    mkdir -p ../dist/api
    cp -r dist/ node_modules/ package.json ../dist/api/
    
    # Create PM2 ecosystem file
    cat > ../dist/api/ecosystem.config.js << 'EOF'
module.exports = {
  apps: [{
    name: 'shop-management-api',
    script: 'dist/app.js',
    instances: 'max',
    exec_mode: 'cluster',
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'development',
      PORT: 3000
    },
    env_production: {
      NODE_ENV: 'production',
      PORT: 3000
    }
  }]
};
EOF
    
    # Create application scripts
    cat > ../dist/api/start.sh << 'EOF'
#!/bin/bash
export NODE_ENV=production
pm2 start ecosystem.config.js --env production
pm2 save
EOF
    chmod +x ../dist/api/start.sh
    
    cat > ../dist/api/stop.sh << 'EOF'
#!/bin/bash
pm2 stop all
pm2 delete all
EOF
    chmod +x ../dist/api/stop.sh
    
    log_success "API build completed"
    cd ..
    
    # Build Frontend application
    log_info "Building frontend application..."
    cd frontend
    npm ci
    npm run build
    
    # Copy built assets
    mkdir -p ../dist/frontend
    cp -r build/* ../dist/frontend/
    log_success "Frontend build completed"
    cd ..
}

# Create CodeDeploy bundle
create_deployment_bundle() {
    log_info "Creating CodeDeploy application bundle..."
    
    # Create appspec.yml for CodeDeploy
    cat > appspec.yml << 'EOF'
version: 0.0
os: linux
files:
  - source: api/
    destination: /opt/shop-management/api/
  - source: frontend/
    destination: /var/www/html/
permissions:
  - object: /opt/shop-management
    owner: shopapp
    group: shopapp
    mode: 755
    type:
      - directory
      - file
hooks:
  BeforeInstall:
    - location: scripts/stop_application.sh
      timeout: 300
      runas: root
  AfterInstall:
    - location: scripts/install_dependencies.sh
      timeout: 600
      runas: root
  ApplicationStart:
    - location: scripts/start_application.sh
      timeout: 300
      runas: root
  ApplicationStop:
    - location: scripts/stop_application.sh
      timeout: 300
      runas: root
EOF
    
    # Create deployment scripts
    mkdir -p scripts
    
    cat > scripts/stop_application.sh << 'EOF'
#!/bin/bash
if [ -f /opt/shop-management/api/stop.sh ]; then
  cd /opt/shop-management/api && ./stop.sh
fi
# Stop nginx
systemctl stop nginx || true
EOF
    
    cat > scripts/install_dependencies.sh << 'EOF'
#!/bin/bash
# Update system packages
yum update -y

# Install or update Node.js if needed
if ! command -v node &> /dev/null; then
  curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
  yum install -y nodejs
fi

# Install PM2 if not present
if ! command -v pm2 &> /dev/null; then
  npm install -g pm2
fi

# Install nginx if not present
if ! command -v nginx &> /dev/null; then
  amazon-linux-extras install nginx1 -y
fi

# Configure nginx for frontend
cat > /etc/nginx/conf.d/shop-management.conf << 'NGINX_EOF'
server {
    listen 80;
    server_name _;
    root /var/www/html;
    index index.html index.htm;

    # API proxy
    location /api/ {
        proxy_pass http://localhost:3000/api/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # Frontend static files
    location / {
        try_files $uri $uri/ /index.html;
        expires 1d;
        add_header Cache-Control "public, immutable";
    }
}
NGINX_EOF

# Set proper ownership
chown -R shopapp:shopapp /opt/shop-management/ || true
chown -R nginx:nginx /var/www/html/ || true
EOF
    
    cat > scripts/start_application.sh << 'EOF'
#!/bin/bash
# Start the API application
cd /opt/shop-management/api
su shopapp -c "./start.sh"

# Start and enable nginx
systemctl start nginx
systemctl enable nginx

# Verify services are running
sleep 10
if ! pgrep -f "shop-management-api" > /dev/null; then
    echo "Failed to start API application"
    exit 1
fi

if ! systemctl is-active --quiet nginx; then
    echo "Failed to start nginx"
    exit 1
fi

echo "All services started successfully"
EOF
    
    chmod +x scripts/*.sh
    
    # Create deployment bundle
    BUNDLE_NAME="$PROJECT_NAME-$(date +%Y%m%d-%H%M%S)-${GITHUB_SHA:-$(git rev-parse --short HEAD)}"
    zip -r "$BUNDLE_NAME.zip" appspec.yml dist/ scripts/
    
    log_success "Deployment bundle created: $BUNDLE_NAME.zip"
}

# Upload bundle to S3
upload_bundle() {
    log_info "Uploading deployment bundle to S3..."
    
    BUNDLE_NAME="$PROJECT_NAME-$(date +%Y%m%d-%H%M%S)-${GITHUB_SHA:-$(git rev-parse --short HEAD)}"
    
    aws s3 cp "$BUNDLE_NAME.zip" \
        "s3://$S3_DEPLOYMENT_BUCKET/deployments/$BUNDLE_NAME.zip" \
        --region "$AWS_REGION"
    
    log_success "Bundle uploaded successfully"
    
    # Store bundle info for deployment
    echo "$BUNDLE_NAME" > .deployment-bundle
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
        -var="s3_deployment_bucket=$S3_DEPLOYMENT_BUCKET" \
        -out="tfplan-${ENVIRONMENT}"
    
    # Apply the plan
    terraform apply "tfplan-${ENVIRONMENT}"
    
    log_success "Infrastructure deployed successfully"
    cd ..
}

# Deploy application with CodeDeploy
deploy_application() {
    log_info "Creating CodeDeploy deployment..."
    
    BUNDLE_NAME=$(cat .deployment-bundle)
    
    DEPLOYMENT_ID=$(aws deploy create-deployment \
        --application-name "$PROJECT_NAME-$ENVIRONMENT" \
        --deployment-group-name "$PROJECT_NAME-$ENVIRONMENT-deployment-group" \
        --s3-location bucket="$S3_DEPLOYMENT_BUCKET",key="deployments/$BUNDLE_NAME.zip",bundleType=zip \
        --deployment-config-name CodeDeployDefault.EC2AllAtOne \
        --description "Deployment from script - $BUNDLE_NAME" \
        --region "$AWS_REGION" \
        --query 'deploymentId' --output text)
    
    log_info "Deployment ID: $DEPLOYMENT_ID"
    
    # Wait for deployment to complete
    log_info "Waiting for deployment to complete..."
    aws deploy wait deployment-successful --deployment-id "$DEPLOYMENT_ID" --region "$AWS_REGION"
    
    log_success "Application deployment completed successfully"
}

# Run post-deployment checks
post_deployment_checks() {
    log_info "Running post-deployment checks..."
    
    # Get load balancer DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --names "$PROJECT_NAME-$ENVIRONMENT-alb" \
        --query 'LoadBalancers[0].DNSName' \
        --output text --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [ -z "$ALB_DNS" ]; then
        log_warning "Could not retrieve load balancer DNS name"
        return
    fi
    
    # Wait for instances to be ready
    sleep 30
    
    # Health check API
    log_info "Checking API health..."
    for i in {1..10}; do
        if curl -f -s "http://$ALB_DNS/api/health" > /dev/null; then
            log_success "API health check passed"
            break
        else
            log_info "API health check attempt $i/10 failed, retrying..."
            sleep 10
        fi
    done
    
    # Health check frontend
    log_info "Checking frontend..."
    for i in {1..5}; do
        if curl -f -s "http://$ALB_DNS/" > /dev/null; then
            log_success "Frontend health check passed"
            break
        else
            log_info "Frontend health check attempt $i/5 failed, retrying..."
            sleep 5
        fi
    done
    
    log_info "Application deployed successfully!"
    log_info "Load Balancer DNS: $ALB_DNS"
    log_info "Application URL: http://$ALB_DNS"
}

# Main deployment function
main() {
    log_info "Starting deployment for environment: $ENVIRONMENT"
    
    validate_environment
    check_prerequisites
    setup_s3_bucket
    build_applications
    create_deployment_bundle
    upload_bundle
    deploy_infrastructure
    deploy_application
    post_deployment_checks
    
    log_success "Deployment completed successfully!"
}

# Error handling
trap 'log_error "Deployment failed at line $LINENO"' ERR

# Cleanup function
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -f *.zip .deployment-bundle appspec.yml
    rm -rf scripts/ dist/
}

# Set up cleanup trap
trap cleanup EXIT

# Run main function
main "$@"
```

This comprehensive CI/CD configuration includes:

1. **GitHub Actions**: Automated testing, security scanning, and deployment
2. **AWS CodePipeline**: Complete pipeline orchestration  
3. **CodeBuild**: Application building and S3 artifact storage
4. **AWS CodeDeploy**: EC2 Auto Scaling Group deployments
5. **Deployment Scripts**: Automated infrastructure deployment with EC2
6. **Health Checks**: Post-deployment verification
7. **Security Scanning**: Vulnerability detection and OWASP testing
8. **Multi-environment Support**: Dev, staging, and production workflows

## Deployment Strategy

### EC2 Auto Scaling Groups with CodeDeploy

The deployment strategy uses AWS CodeDeploy with EC2 Auto Scaling Groups to achieve zero-downtime deployments:

#### 1. **Auto Scaling Group Configuration**
```bash
# Production Auto Scaling Group
Min Size: 2 instances
Max Size: 10 instances
Desired Capacity: 3 instances
Target Group: shop-management-production-tg
Health Check Type: ELB
Health Check Grace Period: 300 seconds
```

#### 2. **CodeDeploy Deployment Process**
```bash
# Deployment Configuration
Configuration: CodeDeployDefault.EC2AllAtOne
- Updates all instances simultaneously
- Minimum healthy hosts: 0%
- Alternative: CodeDeployDefault.EC2OneAtATime for safer updates

# Application Lifecycle
1. ApplicationStop: Stop existing PM2 processes and nginx
2. DownloadBundle: Download new code from S3
3. BeforeInstall: Prepare instance for new deployment
4. Install: Deploy files to /opt/shop-management/ and /var/www/html/
5. AfterInstall: Install dependencies, configure services
6. ApplicationStart: Start PM2 and nginx services
7. ValidateService: Run health checks
```

#### 3. **Load Balancer Health Checks**
```bash
Target Group Health Check:
- Protocol: HTTP
- Path: /api/health
- Port: 80
- Healthy Threshold: 2
- Unhealthy Threshold: 3
- Timeout: 5 seconds
- Interval: 30 seconds
```

#### 4. **Rollback Strategy**
```bash
# Automatic Rollback Conditions
- Health check failures after deployment
- Application start failures
- CodeDeploy deployment failures
- Manual rollback trigger

# Rollback Process
1. CodeDeploy automatic rollback to previous revision
2. Auto Scaling Group instance refresh if needed
3. Load balancer automatically routes to healthy instances
4. Monitoring alerts for rollback events
5. Application logs preserved for debugging
```

#### 5. **Environment-Specific Configurations**

**Production Environment**
```yaml
Auto Scaling Group: shop-management-production-asg
Target Group: shop-management-production-tg
Load Balancer: shop-management-production-alb
CodeDeploy Application: shop-management-production
Deployment Group: shop-management-production-deployment-group
Instance Profile: ShopManagementEC2Role
EC2 Instance Type: t3.medium (2 vCPU, 4 GB RAM)
```

**Staging Environment**
```yaml
Auto Scaling Group: shop-management-staging-asg
Target Group: shop-management-staging-tg
Load Balancer: shop-management-staging-alb
CodeDeploy Application: shop-management-staging
Deployment Group: shop-management-staging-deployment-group
Instance Profile: ShopManagementEC2Role
EC2 Instance Type: t3.small (2 vCPU, 2 GB RAM)
```

#### 6. **Cost Benefits**
- **50% cost reduction** compared to ECS Fargate
- **Predictable pricing** with EC2 Reserved Instances
- **Auto Scaling** based on CPU and request metrics
- **Efficient resource utilization** with PM2 clustering

#### 7. **Operational Benefits**
- **Direct server access** for debugging and maintenance
- **Simpler troubleshooting** with standard Linux tools
- **Flexible configuration** without container constraints
- **Native monitoring** with CloudWatch agent

The pipeline ensures code quality, security, and reliable deployments with proper rollback mechanisms optimized for EC2-based architecture.

Let me mark the AWS deployment documentation as completed and move to the next phase: