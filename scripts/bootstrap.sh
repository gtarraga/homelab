#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"
BACKEND_DIR="$TF_DIR/backend"
BACKEND_CONFIG="$TF_DIR/backend.tfvars"

SSM_SECRETS=(
  "/homelab/cloudflare/terraform/token|Cloudflare API token (Terraform)"
  "/homelab/cloudflare/externaldns/token|Cloudflare API token (ExternalDNS)"
)

setup_hooks() {
  echo "==> Configuring git hooks..."
  git config core.hooksPath .githooks
}

check_prerequisites() {
  local missing=()
  command -v terraform &>/dev/null || missing+=("terraform")
  command -v aws &>/dev/null       || missing+=("aws")
  command -v gh &>/dev/null        || missing+=("gh")

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: missing required tools: ${missing[*]}" >&2
    exit 1
  fi

  echo "Verifying AWS credentials..."
  if ! aws sts get-caller-identity &>/dev/null; then
    echo "ERROR: AWS credentials not configured. Run 'aws configure' or set AWS_PROFILE." >&2
    exit 1
  fi
  echo "AWS identity: $(aws sts get-caller-identity --query 'Arn' --output text)"
}

create_backend() {
  echo ""
  echo "==> Creating S3 state backend..."
  terraform -chdir="$BACKEND_DIR" init -input=false
  terraform -chdir="$BACKEND_DIR" apply -input=false

  echo ""
  echo "==> Generating backend config..."
  local bucket region
  bucket=$(terraform -chdir="$BACKEND_DIR" output -raw bucket)
  region=$(terraform -chdir="$BACKEND_DIR" output -raw region)

  cat > "$BACKEND_CONFIG" <<EOF
bucket       = "${bucket}"
key          = "terraform.tfstate"
region       = "${region}"
encrypt      = true
use_lockfile = true
EOF
  echo "    wrote $BACKEND_CONFIG"
}

bootstrap_main() {
  echo ""
  echo "==> Initializing main Terraform config..."
  terraform -chdir="$TF_DIR" init -input=false -backend-config="$BACKEND_CONFIG"

  echo ""
  echo "==> Applying IAM + SSM placeholders..."
  terraform -chdir="$TF_DIR" apply -input=false \
    -target=module.aws_identity \
    -target=module.aws_ssm
}

prompt_secrets() {
  echo ""
  echo "==> Setting SSM secret values..."
  echo "    (press Enter to skip a secret if already set)"

  for entry in "${SSM_SECRETS[@]}"; do
    local name="${entry%%|*}"
    local label="${entry##*|}"

    read -rsp "$label [$name]: " value
    echo ""

    if [[ -z "$value" ]]; then
      echo "    skipped"
      continue
    fi

    aws ssm put-parameter \
      --name "$name" \
      --value "$value" \
      --type SecureString \
      --overwrite \
      --no-cli-pager
    echo "    set"
  done
}

full_apply() {
  echo ""
  echo "==> Running full Terraform apply..."
  terraform -chdir="$TF_DIR" apply -input=false
}

sync_github_vars() {
  echo ""
  echo "==> Syncing GitHub repo variables..."
  local role_arn region
  role_arn=$(terraform -chdir="$TF_DIR" output -raw github_role_arn)
  region=$(terraform -chdir="$BACKEND_DIR" output -raw region)
  gh variable set AWS_ROLE_ARN --body "$role_arn"
  gh variable set AWS_REGION --body "$region"
  echo "    AWS_ROLE_ARN=$role_arn"
  echo "    AWS_REGION=$region"
}

main() {
  echo "Homelab bootstrap"
  echo "================="
  echo ""

  setup_hooks
  check_prerequisites
  create_backend
  bootstrap_main
  prompt_secrets
  full_apply
  sync_github_vars

  echo ""
  echo "Bootstrap complete."
}

main "$@"
