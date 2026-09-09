pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
    }

    parameters {
        string(
            name: 'APP_VERSION',
            defaultValue: '',
            description: 'Docker image version to deploy. Leave blank for automatic build number.'
        )
    }

    environment {
        AWS_REGION     = 'ap-south-1'
        AWS_ACCOUNT_ID = '849808307461'
        AWS_CLI        = '/usr/local/bin/aws'

        ECR_REPO = '849808307461.dkr.ecr.ap-south-1.amazonaws.com/bluegreen-cicd-app'

        BLUE_TG = 'arn:aws:elasticloadbalancing:ap-south-1:849808307461:targetgroup/bluegreen-cicd-blue-tg/df3f77f6ad1b089c'

        GREEN_TG = 'arn:aws:elasticloadbalancing:ap-south-1:849808307461:targetgroup/bluegreen-cicd-green-tg/1e159b53ced6344e'

        LISTENER_ARN = 'arn:aws:elasticloadbalancing:ap-south-1:849808307461:listener/app/bluegreen-cicd-alb/faf6ba3901e10c70/a83fa517f38eb0ae'

        ALB_DNS = 'bluegreen-cicd-alb-1797378953.ap-south-1.elb.amazonaws.com'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Validate Tools') {
            steps {
                sh '''
                    docker --version
                    $AWS_CLI --version
                    $AWS_CLI sts get-caller-identity
                '''
            }
        }

        stage('Detect Active Environment') {
            steps {
                script {

                    /*
                     * Manual build:
                     * User can enter APP_VERSION such as 1.3.0
                     *
                     * GitHub webhook:
                     * If APP_VERSION is empty, Jenkins automatically
                     * creates a version such as build-8.
                     */

                    def version = params.APP_VERSION?.trim()

                    if (!version) {
                        version = "build-${env.BUILD_NUMBER}"
                    }

                    env.APP_VERSION = version

                    /*
                     * Find BLUE EC2 dynamically using AWS tag.
                     */
                    def blueInstance = sh(
                        script: '''
                            $AWS_CLI ec2 describe-instances \
                              --region "$AWS_REGION" \
                              --filters \
                                "Name=tag:Name,Values=bluegreen-cicd-blue" \
                                "Name=instance-state-name,Values=running" \
                              --query 'Reservations[].Instances[].InstanceId | [0]' \
                              --output text
                        ''',
                        returnStdout: true
                    ).trim()

                    /*
                     * Find GREEN EC2 dynamically using AWS tag.
                     */
                    def greenInstance = sh(
                        script: '''
                            $AWS_CLI ec2 describe-instances \
                              --region "$AWS_REGION" \
                              --filters \
                                "Name=tag:Name,Values=bluegreen-cicd-green" \
                                "Name=instance-state-name,Values=running" \
                              --query 'Reservations[].Instances[].InstanceId | [0]' \
                              --output text
                        ''',
                        returnStdout: true
                    ).trim()

                    /*
                     * Stop pipeline if either server cannot be found.
                     */
                    if (!blueInstance || blueInstance == 'None') {
                        error("Unable to find running BLUE EC2 instance")
                    }

                    if (!greenInstance || greenInstance == 'None') {
                        error("Unable to find running GREEN EC2 instance")
                    }

                    env.BLUE_INSTANCE = blueInstance
                    env.GREEN_INSTANCE = greenInstance

                    echo "Application version: ${env.APP_VERSION}"
                    echo "BLUE instance: ${env.BLUE_INSTANCE}"
                    echo "GREEN instance: ${env.GREEN_INSTANCE}"

                    /*
                     * Find which Target Group currently has weight 100.
                     */
                    def activeTg = sh(
                        script: '''
                            $AWS_CLI elbv2 describe-listeners \
                              --listener-arns "$LISTENER_ARN" \
                              --query 'Listeners[0].DefaultActions[0].ForwardConfig.TargetGroups[?Weight==`100`].TargetGroupArn | [0]' \
                              --output text
                        ''',
                        returnStdout: true
                    ).trim()

                    if (activeTg == env.BLUE_TG) {

                        env.ACTIVE_ENV = 'BLUE'
                        env.ACTIVE_TG = env.BLUE_TG

                        env.DEPLOY_ENV = 'GREEN'
                        env.DEPLOY_TG = env.GREEN_TG
                        env.DEPLOY_INSTANCE = env.GREEN_INSTANCE

                    } else if (activeTg == env.GREEN_TG) {

                        env.ACTIVE_ENV = 'GREEN'
                        env.ACTIVE_TG = env.GREEN_TG

                        env.DEPLOY_ENV = 'BLUE'
                        env.DEPLOY_TG = env.BLUE_TG
                        env.DEPLOY_INSTANCE = env.BLUE_INSTANCE

                    } else {

                        error("Unable to determine active BLUE/GREEN environment")
                    }

                    echo "Current LIVE environment: ${env.ACTIVE_ENV}"
                    echo "Deploying version ${env.APP_VERSION} to: ${env.DEPLOY_ENV}"
                    echo "Deployment instance: ${env.DEPLOY_INSTANCE}"
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    echo "Building Docker image:"
                    echo "$ECR_REPO:$APP_VERSION"

                    docker build \
                      -t "$ECR_REPO:$APP_VERSION" .
                '''
            }
        }

        stage('Test Docker Image') {
            steps {
                sh '''
                    docker rm -f bluegreen-ci-test \
                      >/dev/null 2>&1 || true

                    docker run -d \
                      --name bluegreen-ci-test \
                      -e APP_VERSION="$APP_VERSION" \
                      -e APP_ENVIRONMENT="CI" \
                      -p 18080:80 \
                      "$ECR_REPO:$APP_VERSION"

                    sleep 2

                    curl -fsS \
                      http://localhost:18080 \
                      > ci-response.html

                    grep -q \
                      "Version: $APP_VERSION" \
                      ci-response.html

                    grep -q \
                      "Environment: CI" \
                      ci-response.html

                    echo "Docker image test passed."

                    cat ci-response.html

                    docker rm -f bluegreen-ci-test
                '''
            }
        }

        stage('Push Image to ECR') {
            steps {
                sh '''
                    echo "Logging in to AWS ECR..."

                    $AWS_CLI ecr get-login-password \
                      --region "$AWS_REGION" |
                    docker login \
                      --username AWS \
                      --password-stdin \
                      "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

                    echo "Pushing image:"
                    echo "$ECR_REPO:$APP_VERSION"

                    docker push "$ECR_REPO:$APP_VERSION"
                '''
            }
        }

        stage('Prepare Inactive Environment') {
            steps {
                script {

                    writeFile(
                        file: 'listener-prep.json',
                        text: """[
  {
    "Type": "forward",
    "ForwardConfig": {
      "TargetGroups": [
        {
          "TargetGroupArn": "${env.ACTIVE_TG}",
          "Weight": 100
        },
        {
          "TargetGroupArn": "${env.DEPLOY_TG}",
          "Weight": 0
        }
      ]
    }
  }
]
"""
                    )

                    writeFile(
                        file: 'listener-rollback.json',
                        text: """[
  {
    "Type": "forward",
    "ForwardConfig": {
      "TargetGroups": [
        {
          "TargetGroupArn": "${env.ACTIVE_TG}",
          "Weight": 100
        },
        {
          "TargetGroupArn": "${env.DEPLOY_TG}",
          "Weight": 0
        }
      ]
    }
  }
]
"""
                    )
                }

                sh '''
                    echo "Keeping production on $ACTIVE_ENV"
                    echo "Preparing $DEPLOY_ENV with weight 0"

                    $AWS_CLI elbv2 modify-listener \
                      --listener-arn "$LISTENER_ARN" \
                      --default-actions file://listener-prep.json \
                      >/dev/null
                '''
            }
        }

        stage('Deploy Using SSM') {
            steps {
                script {

                    writeFile(
                        file: 'ssm-params.json',
                        text: """{
  "commands": [
    "set -e",
    "/usr/local/bin/aws ecr get-login-password --region ${env.AWS_REGION} | docker login --username AWS --password-stdin ${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com",
    "docker pull ${env.ECR_REPO}:${env.APP_VERSION}",
    "docker rm -f bluegreen-app >/dev/null 2>&1 || true",
    "docker run -d --name bluegreen-app --restart unless-stopped -e APP_VERSION=${env.APP_VERSION} -e APP_ENVIRONMENT=${env.DEPLOY_ENV} -p 80:80 ${env.ECR_REPO}:${env.APP_VERSION}",
    "docker ps --filter name=bluegreen-app"
  ]
}
"""
                    )
                }

                sh '''
                    echo "Deploying to $DEPLOY_ENV"
                    echo "Instance: $DEPLOY_INSTANCE"

                    COMMAND_ID=$(
                      $AWS_CLI ssm send-command \
                        --instance-ids "$DEPLOY_INSTANCE" \
                        --document-name "AWS-RunShellScript" \
                        --parameters file://ssm-params.json \
                        --query 'Command.CommandId' \
                        --output text
                    )

                    echo "SSM Command ID: $COMMAND_ID"

                    $AWS_CLI ssm wait command-executed \
                      --command-id "$COMMAND_ID" \
                      --instance-id "$DEPLOY_INSTANCE"

                    STATUS=$(
                      $AWS_CLI ssm get-command-invocation \
                        --command-id "$COMMAND_ID" \
                        --instance-id "$DEPLOY_INSTANCE" \
                        --query 'Status' \
                        --output text
                    )

                    echo "SSM deployment status: $STATUS"

                    $AWS_CLI ssm get-command-invocation \
                      --command-id "$COMMAND_ID" \
                      --instance-id "$DEPLOY_INSTANCE" \
                      --query \
                      '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}'

                    if [ "$STATUS" != "Success" ]; then
                        echo "SSM deployment failed."
                        exit 1
                    fi
                '''
            }
        }

        stage('Wait For Health Check') {
            steps {
                sh '''
                    echo "Waiting for $DEPLOY_ENV target to become healthy..."

                    for attempt in $(seq 1 20)
                    do

                        STATE=$(
                          $AWS_CLI elbv2 describe-target-health \
                            --target-group-arn "$DEPLOY_TG" \
                            --targets "Id=$DEPLOY_INSTANCE" \
                            --query \
                            'TargetHealthDescriptions[0].TargetHealth.State' \
                            --output text
                        )

                        echo "Health check attempt $attempt: $STATE"

                        if [ "$STATE" = "healthy" ]; then
                            echo "$DEPLOY_ENV is healthy."
                            exit 0
                        fi

                        sleep 15
                    done

                    echo "$DEPLOY_ENV failed to become healthy."
                    exit 1
                '''
            }
        }

        stage('Switch Production Traffic') {
            steps {
                script {

                    writeFile(
                        file: 'listener-switch.json',
                        text: """[
  {
    "Type": "forward",
    "ForwardConfig": {
      "TargetGroups": [
        {
          "TargetGroupArn": "${env.ACTIVE_TG}",
          "Weight": 0
        },
        {
          "TargetGroupArn": "${env.DEPLOY_TG}",
          "Weight": 100
        }
      ]
    }
  }
]
"""
                    )
                }

                sh '''
                    echo "Switching production traffic..."
                    echo "$ACTIVE_ENV -> $DEPLOY_ENV"

                    $AWS_CLI elbv2 modify-listener \
                      --listener-arn "$LISTENER_ARN" \
                      --default-actions file://listener-switch.json \
                      >/dev/null

                    echo "Traffic switched successfully."
                '''
            }
        }

        stage('Verify Production') {
            steps {
                sh '''
                    SUCCESS=false

                    echo "Verifying production through ALB..."

                    for attempt in $(seq 1 10)
                    do

                        if curl -fsS \
                          "http://$ALB_DNS" \
                          > production-response.html
                        then

                            if grep -q \
                              "Version: $APP_VERSION" \
                              production-response.html &&
                               grep -q \
                              "Environment: $DEPLOY_ENV" \
                              production-response.html
                            then

                                SUCCESS=true
                                break
                            fi
                        fi

                        echo "Production verification attempt $attempt failed."

                        sleep 5
                    done

                    if [ "$SUCCESS" = "true" ]; then

                        echo "================================="
                        echo "DEPLOYMENT SUCCESSFUL"
                        echo "================================="

                        echo "Version: $APP_VERSION"
                        echo "Environment: $DEPLOY_ENV"

                        cat production-response.html

                        exit 0
                    fi

                    echo "================================="
                    echo "PRODUCTION VERIFICATION FAILED"
                    echo "================================="

                    echo "Rolling traffic back to $ACTIVE_ENV..."

                    $AWS_CLI elbv2 modify-listener \
                      --listener-arn "$LISTENER_ARN" \
                      --default-actions file://listener-rollback.json \
                      >/dev/null

                    echo "Rollback completed."
                    echo "$ACTIVE_ENV is LIVE again."

                    exit 1
                '''
            }
        }
    }

    post {

        success {
            echo 'Blue/Green deployment completed successfully.'
        }

        failure {
            echo 'Pipeline failed. Review the failed stage before retrying.'
        }

        always {
            sh '''
                docker rm -f bluegreen-ci-test \
                  >/dev/null 2>&1 || true

                rm -f listener-prep.json
                rm -f listener-switch.json
                rm -f listener-rollback.json
                rm -f ssm-params.json
                rm -f ci-response.html
                rm -f production-response.html
            '''
        }
    }
}