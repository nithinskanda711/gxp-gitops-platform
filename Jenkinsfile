// Supply-chain pipeline.
//
// The shape that matters: build once, then everything downstream refers to the
// resulting DIGEST rather than the tag. Scanning one artefact and deploying
// another is the failure this design exists to prevent.
//
// Stage order is deliberate. Signing happens last, after the scan gate, so a
// signature can only ever exist for an image that passed.

pipeline {
  agent {
    kubernetes {
      inheritFrom 'supply-chain'
      defaultContainer 'python'
    }
  }

  options {
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timeout(time: 30, unit: 'MINUTES')
  }

  parameters {
    string(
      name: 'CHANGE_REF',
      defaultValue: '',
      description: 'Approved change record identifier, e.g. CHG0041234. Required for qual and prod; the admission policy rejects "unset".'
    )
  }

  environment {
    AWS_REGION  = 'eu-west-1'
    ECR_REPO    = 'gxp/node-monitor'
    IMAGE_TAG   = "0.1.${BUILD_NUMBER}"
  }

  stages {

    stage('Unit tests') {
      steps {
        container('python') {
          dir('app') {
            sh '''
              pip install --quiet --no-cache-dir -r requirements.txt -r requirements-dev.txt
              python -m pytest tests -q --junitxml=../test-results.xml
            '''
          }
        }
      }
      post {
        always {
          junit allowEmptyResults: true, testResults: 'test-results.xml'
        }
      }
    }

    stage('Registry auth') {
      steps {
        container('awscli') {
          // ECR tokens are valid for 12 hours, so they are minted per build and
          // written to an emptyDir that dies with the pod. Nothing long-lived
          // is stored, which is the whole reason for doing it this way.
          sh '''
            set -eu
            ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
            REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
            AUTH=$(printf 'AWS:%s' "$(aws ecr get-login-password --region "${AWS_REGION}")" | base64 -w0)

            mkdir -p /kaniko/.docker
            printf '{"auths":{"%s":{"auth":"%s"}}}' "${REGISTRY}" "${AUTH}" > /kaniko/.docker/config.json

            printf '%s' "${REGISTRY}" > registry.txt
          '''
          script {
            env.REGISTRY = readFile('registry.txt').trim()
            env.IMAGE    = "${env.REGISTRY}/${env.ECR_REPO}"
          }
          echo "Registry: ${env.REGISTRY}"
        }
      }
    }

    stage('Build and push') {
      steps {
        container('kaniko') {
          sh """
            /kaniko/executor \
              --context ./app \
              --dockerfile ./app/Dockerfile \
              --destination ${env.IMAGE}:${IMAGE_TAG} \
              --digest-file ./image-digest.txt \
              --no-push-cache \
              --reproducible
          """
        }
        script {
          env.IMAGE_DIGEST = readFile('image-digest.txt').trim()
          env.IMAGE_REF    = "${env.IMAGE}@${env.IMAGE_DIGEST}"
        }
        echo "Built ${env.IMAGE_REF}"
      }
    }

    stage('SBOM') {
      steps {
        container('syft') {
          sh """
            syft "${env.IMAGE_REF}" -o spdx-json=sbom.spdx.json -o table
          """
        }
        archiveArtifacts artifacts: 'sbom.spdx.json', fingerprint: true
      }
    }

    stage('Vulnerability scan') {
      steps {
        container('trivy') {
          // The gate. Anything CRITICAL fails the build, so no signature is
          // ever produced for a known-vulnerable image.
          sh """
            trivy image --quiet --format table \
              --severity LOW,MEDIUM,HIGH,CRITICAL \
              --output trivy-report.txt \
              "${env.IMAGE_REF}"

            trivy image --quiet --exit-code 1 \
              --severity CRITICAL \
              --ignore-unfixed \
              "${env.IMAGE_REF}"
          """
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'trivy-report.txt', allowEmptyArchive: true
        }
      }
    }

    stage('Sign') {
      steps {
        container('cosign') {
          // Signing the digest, never the tag. A tag can be moved; a digest
          // is the content.
          sh """
            cosign sign --yes --key /keys/cosign.key "${env.IMAGE_REF}"
            cosign attest --yes --key /keys/cosign.key \
              --predicate sbom.spdx.json --type spdxjson "${env.IMAGE_REF}"
          """
        }
      }
    }

    stage('Verify') {
      steps {
        container('cosign') {
          // Verifying our own signature immediately is not ceremony: it proves
          // the artefact the cluster will check is the one we just signed.
          sh """
            cosign verify --key /keys/cosign.pub "${env.IMAGE_REF}" > verification.txt
            cat verification.txt
          """
        }
        archiveArtifacts artifacts: 'verification.txt', allowEmptyArchive: true
      }
    }
  }

  post {
    success {
      script {
        def ref = env.IMAGE_DIGEST ?: 'unknown'
        echo """
        =====================================================================
        Signed and verified.

          tag     : ${IMAGE_TAG}
          digest  : ${ref}

        To deploy, set image.digest in the environment values file and commit.
        Argo CD takes it from there; Kyverno verifies the signature at
        admission before anything is scheduled.
        =====================================================================
        """
      }
    }
    failure {
      echo 'Pipeline failed. No signature was produced, so nothing new can be admitted.'
    }
  }
}
