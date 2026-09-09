pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    parameters {
        string(
            name: 'APP_VERSION',
            defaultValue: '1.2.0',
            description: 'Docker image version to deploy'
        )
    }

    environment {
        AWS_REGION     = 'ap-south-1'
        AWS_ACCOUNT_ID = '849808307461'
        AWS_CLI        = '/usr/local/bin/aws'

        ECR_REPO = '849808307461.dkr.ecr.ap-south-1.amazonaws.com/bluegreen-cicd-app'

        BLUE_INSTANCE  = 'i-0d6bdc2e55911bfb5'
        GREEN_INSTANCE = 'i-090717305108a64a3'

        BLUE_TG  = 'arn:aws:elasticloadbalancing:ap-south-1:849808307461:targetgroup/bluegreen-cicd-blue-tg/df3f77f6ad1b089c'
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
                        env.ACTIVE_ENV      = 'BLUE'
                        env.ACTIVE_TG       = env.BLUE_TG
                        env.DEPLOY_ENV      = 'GREEN'
                        env.DEPLOY_TG       = env.GREEN_TG
                        env.DEPLOY_INSTANCE = env.GREEN_INSTANCE
                    } else if (activeTg == env.GREEN_TG) {
                        env.ACTIVE_ENV      = 'GREEN'
                        env.ACTIVE_TG       = env.GREEN_TG
                        env.DEPLOY_ENV      = 'BLUE'
                        env.DEPLOY_TG       = env.BLUE_TG
                        env.DEPLOY_INSTANCE = env.BLUE_INSTANCE
                    } else {
                        error("Unable to determine active BLUE/GREEN environment")
                    }

                    echo "Current LIVE environment: ${env.ACTIVE_ENV}"
                    echo "Deploying version ${params.APP_VERSION} to: ${env.DEPLOY_ENV}"
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    docker build \
                      -t "$ECR_REPO:$APP_VERSION" .
                '''
            }
        }

        stage('Test Docker Image') {
            steps {
                sh '''
                    docker rm -f bluegreen-ci-test >/dev/null 2>&1 || true

                    docker run -d \
                      --name bluegreen-ci-test \
                      -e APP_VERSION="$APP_VERSION" \
                      -e APP_ENVIRONMENT="CI" \
                      -p 18080:80 \
                      "$ECR_REPO:$APP_VERSION"

                    sleep 2

                    curl -fsS http://localhost:18080 > ci-response.html

                    grep -q "Version: $APP_VERSION" ci-response.html
                    grep -q "Environment: CI" ci-response.html

                    docker rm -f bluegreen-ci-test
                '''
            }
        }

        stage('Push Image to ECR') {
            steps {
                sh '''
                    $AWS_CLI ecr get-login-password \
                      --region "$AWS_REGION" |
                    docker login \
                      --username AWS \
                      --password-stdin \
                      "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

                    docker push "$ECR_REPO:$APP_VERSION"
                '''
            }
        }

        stage('Prepare Inactive Environment') {
            steps {
                sh '''
                    cat > listener-prep.json <<EOF
[
  {
    "Type": "forward",
    "ForwardConfig": {
      "TargetGroups": [
        {
          "TargetGroupArn": "$ACTIVE_TG",
          "Weight": 100
        },
        {
          "TargetGroupArn": "$DEPLOY_TG",
          "Weight": 0
        }
      ]
    }
  }
]
EOF

                    $AWS_CLI elbv2 modify-listener \
                      --listener-arn "$LISTENER_ARN" \
                      --default-actions file://listener-prep.json \
                      >/dev/null
                '''
            }
        }

        stage('Deploy Using SSM') {
            steps {
                sh '''
                    cat > ssm-params.json <<EOF
{
  "commands": [
    "set -e",
    "/usr/local/bin/aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com",
    "docker pull $ECR_REPO:$APP_VERSION",
    "docker rm -f bluegreen-app >/dev/null 2>&1 || true",
    "docker run -d --name bluegreen-app --restart unless-stopped -e APP_VERSION=$APP_VERSION -e APP_ENVIRONMENT=$DEPLOY_ENV -p 80:80 $ECR_REPO:$APP_VERSION",
    "docker ps --filter name=bluegreen-app"
  ]
}
EOF

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

                    $AWS_CLI ssm get-command-invocation \
                      --command-id "$COMMAND_ID" \
                      --instance-id "$DEPLOY_INSTANCE" \
                      --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}'
                '''
            }
        }

        stage('Wait For Health Check') {
            steps {
                sh '''
                    for attempt in $(seq 1 20)
                    do
                        STATE=$(
                          $AWS_CLI elbv2 describe-target-health \
                            --target-group-arn "$DEPLOY_TG" \
                            --targets "Id=$DEPLOY_INSTANCE" \
                            --query 'TargetHealthDescriptions[0].TargetHealth.State' \
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
                sh '''
                    cat > listener-switch.json <<EOF
[
  {
    "Type": "forward",
    "ForwardConfig": {
      "TargetGroups": [
        {
          "TargetGroupArn": "$ACTIVE_TG",
          "Weight": 0
        },
        {
          "TargetGroupArn": "$DEPLOY_TG",
          "Weight": 100
        }
      ]
    }
  }
]
EOF

                    $AWS_CLI elbv2 modify-listener \
                      --listener-arn "$LISTENER_ARN" \
                      --default-actions file://listener-switch.json \
                      >/dev/null

                    echo "Traffic switched: $ACTIVE_ENV -> $DEPLOY_ENV"
                '''
            }
        }

        stage('Verify Production') {
            steps {
                sh '''
                    SUCCESS=false

                    for attempt in $(seq 1 10)
                    do
                        if curl -fsS "http://$ALB_DNS" > production-response.html
                        then
                            if grep -q "Version: $APP_VERSION" production-response.html &&
                               grep -q "Environment: $DEPLOY_ENV" production-response.html
                            then
                                SUCCESS=true
                                break
                            fi
                        fi

                        echo "Production verification attempt $attempt failed."
                        sleep 5
                    done

                    if [ "$SUCCESS" = "true" ]; then
                        echo "Deployment verified successfully."
                        cat production-response.html
                        exit 0
                    fi

                    echo "Verification failed. Rolling traffic back to $ACTIVE_ENV."

                    cat > listener-rollback.json <<EOF
[
  {
    "Type": "forward",
    "ForwardConfig": {
      "TargetGroups": [
        {
          "TargetGroupArn": "$ACTIVE_TG",
          "Weight": 100
        },
        {
          "TargetGroupArn": "$DEPLOY_TG",
          "Weight": 0
        }
      ]
    }
  }
]
EOF

                    $AWS_CLI elbv2 modify-listener \
                      --listener-arn "$LISTENER_ARN" \
                      --default-actions file://listener-rollback.json \
                      >/dev/null

                    echo "Rollback completed."
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
                docker rm -f bluegreen-ci-test >/dev/null 2>&1 || true
                rm -f listener-prep.json listener-switch.json listener-rollback.json
                rm -f ssm-params.json ci-response.html production-response.html
            '''
        }
    }
}