// ============================================================================
// Jenkins pipeline for paved-road-ai-eks
// ============================================================================
// Full lifecycle: Terraform → EKS bootstrap → ArgoCD → workloads → smoke tests.
// Parameterised so the same pipeline handles plan / apply / destroy.
//
// Prerequisites on the Jenkins agent:
//   - terraform >= 1.9.8
//   - kubectl >= 1.30
//   - aws CLI v2
//   - helm 3.x
//   - curl, jq, git
//
// Required Jenkins credentials (add via Manage Jenkins → Credentials):
//   - aws-credentials       (username/password: AccessKey / SecretKey)
//   - grafana-admin-password (secret text)
//   - huggingface-token     (secret text)
// ============================================================================

pipeline {
    agent any

    options {
        timestamps()
        ansiColor('xterm')
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 60, unit: 'MINUTES')
        disableConcurrentBuilds()
    }

    parameters {
        choice(
            name: 'ACTION',
            choices: ['plan', 'apply', 'destroy'],
            description: 'What should this pipeline do?'
        )
        choice(
            name: 'ENVIRONMENT',
            choices: ['dev', 'prod'],
            description: 'Target environment'
        )
        booleanParam(
            name: 'AUTO_APPROVE',
            defaultValue: false,
            description: 'Skip manual approval gate (use with caution)'
        )
        booleanParam(
            name: 'DEPLOY_WORKLOADS',
            defaultValue: true,
            description: 'Deploy Mistral 7B after apply completes'
        )
        booleanParam(
            name: 'RUN_SMOKE_TESTS',
            defaultValue: true,
            description: 'Run inference smoke test after deploy'
        )
    }

    environment {
        AWS_REGION      = 'us-east-1'
        CLUSTER_NAME    = "paved-road-ai-${params.ENVIRONMENT}"
        TF_DIR          = "terraform/envs/${params.ENVIRONMENT}"
        TF_IN_AUTOMATION = 'true'
        TF_INPUT        = 'false'
    }

    stages {

        // --------------------------------------------------------------------
        // Stage 1: Checkout and print context
        // --------------------------------------------------------------------
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()
                }
                echo """
                ================================================================
                Pipeline run for paved-road-ai-eks
                ----------------------------------------------------------------
                Action:            ${params.ACTION}
                Environment:       ${params.ENVIRONMENT}
                Cluster name:      ${env.CLUSTER_NAME}
                Region:            ${env.AWS_REGION}
                Git commit:        ${env.GIT_COMMIT_SHORT}
                Auto-approve:      ${params.AUTO_APPROVE}
                Deploy workloads:  ${params.DEPLOY_WORKLOADS}
                Run smoke tests:   ${params.RUN_SMOKE_TESTS}
                ================================================================
                """
            }
        }

        // --------------------------------------------------------------------
        // Stage 2: Verify tools are installed on the agent
        // Fails fast if a required binary is missing.
        // --------------------------------------------------------------------
        stage('Verify Tools') {
            steps {
                sh '''
                    echo "==> Terraform version:"
                    terraform version
                    echo "==> kubectl version:"
                    kubectl version --client
                    echo "==> aws CLI version:"
                    aws --version
                    echo "==> helm version:"
                    helm version --short
                '''
            }
        }

        // --------------------------------------------------------------------
        // Stage 3: Static analysis — run in parallel to save time
        // --------------------------------------------------------------------
        stage('Static Analysis') {
            parallel {
                stage('Terraform fmt') {
                    steps {
                        sh 'terraform fmt -check -recursive terraform/'
                    }
                }
                stage('Terraform validate') {
                    steps {
                        dir(env.TF_DIR) {
                            sh '''
                                terraform init -backend=false -input=false
                                terraform validate
                            '''
                        }
                    }
                }
                stage('TFLint') {
                    steps {
                        sh '''
                            if command -v tflint >/dev/null 2>&1; then
                                tflint --init
                                tflint --recursive --minimum-failure-severity=warning
                            else
                                echo "tflint not installed — skipping (install for stricter linting)"
                            fi
                        '''
                    }
                }
                stage('Security scan') {
                    steps {
                        sh '''
                            if command -v trivy >/dev/null 2>&1; then
                                trivy config --severity HIGH,CRITICAL --exit-code 0 terraform/
                            else
                                echo "trivy not installed — skipping (install for security scanning)"
                            fi
                        '''
                    }
                }
            }
        }

        // --------------------------------------------------------------------
        // Stage 4: Terraform Plan
        // Always runs. Plan file is archived for review.
        // --------------------------------------------------------------------
        stage('Terraform Plan') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-credentials',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    ),
                    string(
                        credentialsId: 'grafana-admin-password',
                        variable: 'TF_VAR_grafana_admin_password'
                    )
                ]) {
                    dir(env.TF_DIR) {
                        sh '''
                            terraform init -input=false
                            terraform plan \
                                -input=false \
                                -out=tfplan \
                                -detailed-exitcode || plan_exit=$?

                            # Exit code 2 means changes present; 0 means no-op; other = error
                            if [ "${plan_exit:-0}" = "1" ]; then
                                echo "Terraform plan failed"
                                exit 1
                            fi

                            # Human-readable plan output for archival
                            terraform show -no-color tfplan > tfplan.txt
                        '''
                    }
                    archiveArtifacts artifacts: "${env.TF_DIR}/tfplan.txt", fingerprint: true
                }
            }
        }

        // --------------------------------------------------------------------
        // Stage 5: Manual approval before apply or destroy
        // Skipped if AUTO_APPROVE is checked (dev only).
        // --------------------------------------------------------------------
        stage('Approval') {
            when {
                allOf {
                    expression { params.ACTION in ['apply', 'destroy'] }
                    expression { !params.AUTO_APPROVE }
                }
            }
            steps {
                script {
                    def message = params.ACTION == 'destroy' ?
                        "DESTROY the ${params.ENVIRONMENT} environment? Review tfplan.txt in build artifacts first." :
                        "APPLY the plan to ${params.ENVIRONMENT}? Review tfplan.txt in build artifacts first."
                    timeout(time: 15, unit: 'MINUTES') {
                        input(
                            message: message,
                            ok: "Yes, proceed with ${params.ACTION}"
                        )
                    }
                }
            }
        }

        // --------------------------------------------------------------------
        // Stage 6: Terraform Apply
        // --------------------------------------------------------------------
        stage('Terraform Apply') {
            when { expression { params.ACTION == 'apply' } }
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-credentials',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    ),
                    string(
                        credentialsId: 'grafana-admin-password',
                        variable: 'TF_VAR_grafana_admin_password'
                    )
                ]) {
                    dir(env.TF_DIR) {
                        sh 'terraform apply -input=false -auto-approve tfplan'
                    }
                }
            }
        }

        // --------------------------------------------------------------------
        // Stage 7: Configure kubectl for the newly-created cluster
        // --------------------------------------------------------------------
        stage('Configure kubectl') {
            when { expression { params.ACTION == 'apply' } }
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-credentials',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {
                    sh '''
                        aws eks update-kubeconfig \
                            --name ${CLUSTER_NAME} \
                            --region ${AWS_REGION}

                        echo "==> Verifying cluster access:"
                        kubectl get nodes -o wide
                        kubectl get pods -A
                    '''
                }
            }
        }

        // --------------------------------------------------------------------
        // Stage 8: Bootstrap ArgoCD
        // Installs ArgoCD if not present, then applies the root Application.
        // --------------------------------------------------------------------
        stage('Bootstrap ArgoCD') {
            when { expression { params.ACTION == 'apply' } }
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-credentials',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {
                    sh '''
                        if ! kubectl get ns argocd >/dev/null 2>&1; then
                            echo "==> Installing ArgoCD:"
                            kubectl create namespace argocd
                            kubectl apply -n argocd \
                                -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

                            echo "==> Waiting for ArgoCD server:"
                            kubectl wait --for=condition=available \
                                --timeout=300s \
                                deployment/argocd-server -n argocd
                        else
                            echo "==> ArgoCD already installed"
                        fi

                        echo "==> Applying root Application:"
                        kubectl apply -f apps/bootstrap/application.yaml
                    '''
                }
            }
        }

        // --------------------------------------------------------------------
        // Stage 9: Wait for platform components to sync
        // --------------------------------------------------------------------
        stage('Wait for Platform Sync') {
            when { expression { params.ACTION == 'apply' } }
            steps {
                sh '''
                    echo "==> Waiting for KServe to become ready (up to 10 min):"
                    for i in $(seq 1 60); do
                        if kubectl get deployment -n kserve kserve-controller-manager >/dev/null 2>&1; then
                            kubectl wait --for=condition=available \
                                --timeout=60s \
                                deployment/kserve-controller-manager \
                                -n kserve && break
                        fi
                        echo "  Attempt $i/60 — KServe not ready yet, retrying in 10s"
                        sleep 10
                    done

                    echo "==> Platform components status:"
                    kubectl get pods -A | grep -v Running | grep -v Completed || echo "All pods healthy"
                '''
            }
        }

        // --------------------------------------------------------------------
        // Stage 10: Deploy workloads (Mistral 7B)
        // --------------------------------------------------------------------
        stage('Deploy Workloads') {
            when {
                allOf {
                    expression { params.ACTION == 'apply' }
                    expression { params.DEPLOY_WORKLOADS }
                }
            }
            steps {
                withCredentials([
                    string(
                        credentialsId: 'huggingface-token',
                        variable: 'HF_TOKEN'
                    )
                ]) {
                    sh '''
                        # Create inference namespace and HF token secret
                        kubectl create namespace inference --dry-run=client -o yaml | kubectl apply -f -
                        kubectl create secret generic huggingface-token \
                            --from-literal=token="${HF_TOKEN}" \
                            --namespace inference \
                            --dry-run=client -o yaml | kubectl apply -f -

                        # Deploy Mistral
                        kubectl apply -k apps/workloads/mistral-7b/

                        echo "==> Waiting for Mistral pod to be scheduled:"
                        kubectl wait --for=condition=PodScheduled \
                            pod -l app=mistral-7b \
                            -n inference \
                            --timeout=600s

                        echo "==> Mistral pod status (loading may take 3–5 min more):"
                        kubectl get pods -n inference -l app=mistral-7b
                    '''
                }
            }
        }

        // --------------------------------------------------------------------
        // Stage 11: Smoke tests — verify inference works
        // --------------------------------------------------------------------
        stage('Smoke Tests') {
            when {
                allOf {
                    expression { params.ACTION == 'apply' }
                    expression { params.DEPLOY_WORKLOADS }
                    expression { params.RUN_SMOKE_TESTS }
                }
            }
            steps {
                sh '''
                    echo "==> Waiting for Mistral readiness (up to 10 min for model load):"
                    kubectl wait --for=condition=ready \
                        pod -l app=mistral-7b \
                        -n inference \
                        --timeout=600s

                    echo "==> Port-forwarding to run inference test:"
                    kubectl port-forward -n inference svc/mistral-7b-predictor 8080:80 &
                    PF_PID=$!
                    sleep 10

                    echo "==> Sending test inference request:"
                    RESPONSE=$(curl -sf -X POST http://localhost:8080/v1/completions \
                        -H "Content-Type: application/json" \
                        -d '{
                            "model": "mistral-7b",
                            "prompt": "Kubernetes is",
                            "max_tokens": 20
                        }')

                    kill $PF_PID 2>/dev/null || true

                    if echo "$RESPONSE" | jq -e '.choices[0].text' >/dev/null; then
                        echo "==> Smoke test PASSED"
                        echo "$RESPONSE" | jq .
                    else
                        echo "==> Smoke test FAILED — response was:"
                        echo "$RESPONSE"
                        exit 1
                    fi
                '''
            }
        }

        // --------------------------------------------------------------------
        // Stage 12: Terraform Destroy
        // --------------------------------------------------------------------
        stage('Terraform Destroy') {
            when { expression { params.ACTION == 'destroy' } }
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-credentials',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    ),
                    string(
                        credentialsId: 'grafana-admin-password',
                        variable: 'TF_VAR_grafana_admin_password'
                    )
                ]) {
                    dir(env.TF_DIR) {
                        sh '''
                            # Delete workloads first to release GPU nodes
                            kubectl delete inferenceservice --all -A --ignore-not-found=true --timeout=60s || true
                            kubectl delete namespace inference --ignore-not-found=true --timeout=120s || true

                            # Now destroy infrastructure
                            terraform destroy -input=false -auto-approve
                        '''
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------------
    // Post actions — always run, regardless of success/failure
    // ------------------------------------------------------------------------
    post {
        always {
            script {
                // Capture kubectl state for debugging if we got that far
                sh '''
                    if kubectl cluster-info >/dev/null 2>&1; then
                        echo "==> Capturing cluster state:"
                        mkdir -p diagnostic-logs
                        kubectl get pods -A -o wide > diagnostic-logs/pods.txt 2>/dev/null || true
                        kubectl get nodes -o wide > diagnostic-logs/nodes.txt 2>/dev/null || true
                        kubectl get events -A --sort-by=.lastTimestamp > diagnostic-logs/events.txt 2>/dev/null || true
                    fi
                '''
                archiveArtifacts artifacts: 'diagnostic-logs/**', allowEmptyArchive: true
            }
            cleanWs(
                cleanWhenNotBuilt: false,
                deleteDirs: true,
                notFailBuild: true,
                patterns: [
                    [pattern: '**/.terraform/**', type: 'INCLUDE'],
                    [pattern: '**/tfplan', type: 'INCLUDE']
                ]
            )
        }
        success {
            echo """
            ================================================================
            Pipeline SUCCEEDED
            Action:      ${params.ACTION}
            Environment: ${params.ENVIRONMENT}
            Git commit:  ${env.GIT_COMMIT_SHORT}
            ================================================================
            """
        }
        failure {
            echo """
            ================================================================
            Pipeline FAILED
            Action:      ${params.ACTION}
            Environment: ${params.ENVIRONMENT}
            Check diagnostic-logs/ in build artifacts for cluster state.
            ================================================================
            """
        }
    }
}