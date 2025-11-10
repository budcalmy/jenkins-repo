pipeline {
    agent any
    
    environment {
        AWS_ACCOUNT_ID = "486205206788"
        AWS_REGION = "us-east-1"
        ECR_REGISTRY = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        IMAGE_NAME = "multiarch/task15"
        IMAGE_TAG = "nginx-base-1.0"
        ECR_IMAGE = "${ECR_REGISTRY}/${IMAGE_NAME}"
        DOCKER_BUILDKIT = "1"
        IMAGE_KEEP = "10"
        
        EC2_DEV_HOST = "54.91.253.98"
        EC2_DEV_USER = "ubuntu"
        EC2_PROD_HOST = "52.201.246.148"
        EC2_PROD_USER = "ubuntu"
        
        DEV_CONTAINER_NAME = "dev-nginx"
        PROD_CONTAINER_NAME = "prod-nginx"
        CONTAINER_PORT = "80"
    }
    
    stages {
        stage('Validate') {
            steps {
                script {
                    sh '''
                        echo "==> Validating environment..."
                        command -v docker >/dev/null || { echo "docker missing on runner"; exit 1; }
                        command -v aws >/dev/null || { echo "aws cli missing"; exit 1; }
                        echo "✓ Docker version: $(docker --version)"
                        echo "✓ AWS CLI version: $(aws --version)"
                        echo "✓ Validation OK on $(hostname)"
                    '''
                }
            }
        }
        
        stage('Build & Push Dev') {
            when {
                branch 'dev'
            }
            steps {
                script {
                    withAWS(credentials: 'aws-ecr-credentials', region: "${AWS_REGION}") {
                        env.COMMIT_TAG = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
                        
                        sh '''
                            echo "==> Logging into ECR..."
                            aws ecr get-login-password --region "$AWS_REGION" | docker login \
                                --username AWS \
                                --password-stdin "$ECR_REGISTRY"
                            
                            echo "==> Ensuring ECR repository exists..."
                            aws ecr describe-repositories --repository-names "$IMAGE_NAME" --region "$AWS_REGION" >/dev/null 2>&1 || \
                                aws ecr create-repository --repository-name "$IMAGE_NAME" \
                                    --image-scanning-configuration scanOnPush=true \
                                    --image-tag-mutability MUTABLE \
                                    --region "$AWS_REGION"
                            
                            echo "==> Setting up buildx for multi-arch build..."
                            docker buildx create --name multiarch --use 2>/dev/null || docker buildx use multiarch
                            docker buildx inspect --bootstrap
                            
                            echo "==> Building and pushing multi-arch image (amd64 + arm64) with commit tag and dev-latest..."
                            docker buildx build \
                                --platform linux/amd64,linux/arm64 \
                                -t "$ECR_IMAGE:$COMMIT_TAG" \
                                -t "$ECR_IMAGE:dev-latest" \
                                --push .
                            
                            echo "==> Saving commit tag to artifact..."
                            echo "$COMMIT_TAG" > dev_commit_tag.txt
                        '''
                        
                        // Архивируем артефакт
                        archiveArtifacts artifacts: 'dev_commit_tag.txt', fingerprint: true
                    }
                }
            }
        }
        
        stage('Build & Push Prod') {
            when {
                allOf {
                    branch 'main'
                    expression { 
                        def commitMsg = sh(returnStdout: true, script: 'git log -1 --pretty=%B').trim()
                        return commitMsg.startsWith('Merge')
                    }
                }
            }
            steps {
                script {
                    withAWS(credentials: 'aws-ecr-credentials', region: "${AWS_REGION}") {
                        env.COMMIT_TAG = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
                        
                        sh '''
                            echo "==> Logging into ECR..."
                            aws ecr get-login-password --region "$AWS_REGION" | docker login \
                                --username AWS \
                                --password-stdin "$ECR_REGISTRY"
                            
                            echo "==> Ensuring ECR repository exists..."
                            aws ecr describe-repositories --repository-names "$IMAGE_NAME" --region "$AWS_REGION" >/dev/null 2>&1 || \
                                aws ecr create-repository --repository-name "$IMAGE_NAME" \
                                    --image-scanning-configuration scanOnPush=true \
                                    --image-tag-mutability MUTABLE \
                                    --region "$AWS_REGION"
                            
                            echo "==> Setting up buildx for multi-arch build..."
                            docker buildx create --name multiarch --use 2>/dev/null || docker buildx use multiarch
                            docker buildx inspect --bootstrap
                            
                            echo "==> Building and pushing multi-arch prod image (amd64 + arm64)..."
                            docker buildx build \
                                --platform linux/amd64,linux/arm64 \
                                -t "$ECR_IMAGE:$COMMIT_TAG" \
                                -t "$ECR_IMAGE:prod-latest" \
                                --push .
                            
                            echo "==> Saving commit tag to artifact..."
                            echo "$COMMIT_TAG" > prod_commit_tag.txt
                        '''
                        
                        archiveArtifacts artifacts: 'prod_commit_tag.txt', fingerprint: true
                    }
                }
            }
        }
        
        stage('Deploy to EC2 Dev') {
            when {
                branch 'dev'
            }
            steps {
                script {
                    sshagent(['ec2-ssh-key']) {
                        sh '''
                            chmod +x scripts/remote_deploy.sh
                            
                            echo "==> Deploying dev image to EC2 $EC2_DEV_HOST"
                            
                            # Читаем commit tag если есть
                            if [ -f "dev_commit_tag.txt" ]; then
                                COMMIT_TAG=$(cat dev_commit_tag.txt)
                                echo "Commit tag: $COMMIT_TAG"
                            fi
                            
                            echo "Using image $ECR_IMAGE:dev-latest"
                            
                            bash scripts/remote_deploy.sh \
                                "$EC2_DEV_HOST" \
                                "$EC2_DEV_USER" \
                                "$AWS_REGION" \
                                "$ECR_REGISTRY" \
                                "$ECR_IMAGE" \
                                "dev-latest" \
                                "$DEV_CONTAINER_NAME" \
                                "$CONTAINER_PORT"
                            
                            echo "✅ Dev deployment complete!"
                        '''
                    }
                }
            }
        }
        
        stage('Deploy to EC2 Prod') {
            when {
                allOf {
                    branch 'main'
                    expression { 
                        def commitMsg = sh(returnStdout: true, script: 'git log -1 --pretty=%B').trim()
                        return commitMsg.startsWith('Merge')
                    }
                }
            }
            steps {
                script {
                    sshagent(['ec2-ssh-key']) {
                        sh '''
                            chmod +x scripts/remote_deploy.sh
                            
                            echo "==> Deploying prod image to EC2 $EC2_PROD_HOST"
                            
                            # Читаем commit tag если есть
                            if [ -f "prod_commit_tag.txt" ]; then
                                COMMIT_TAG=$(cat prod_commit_tag.txt)
                                echo "Commit tag: $COMMIT_TAG"
                            fi
                            
                            echo "Using image $ECR_IMAGE:prod-latest"
                            
                            bash scripts/remote_deploy.sh \
                                "$EC2_PROD_HOST" \
                                "$EC2_PROD_USER" \
                                "$AWS_REGION" \
                                "$ECR_REGISTRY" \
                                "$ECR_IMAGE" \
                                "prod-latest" \
                                "$PROD_CONTAINER_NAME" \
                                "$CONTAINER_PORT"
                            
                            echo "✅ Prod deployment complete!"
                        '''
                    }
                }
            }
        }
    }
    
    post {
        success {
            echo '✅ Pipeline completed successfully!'
        }
        failure {
            echo '❌ Pipeline failed! Check logs above.'
        }
        always {
            // Очистка workspace (опционально)
            cleanWs(cleanWhenNotBuilt: false,
                    deleteDirs: true,
                    disableDeferredWipeout: true,
                    notFailBuild: true)
        }
    }
}