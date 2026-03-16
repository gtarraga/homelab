#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"

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

bootstrap_aws_modules() {
  echo ""
  echo "==> Initializing Terraform..."
  terraform -chdir="$TF_DIR" init -input=false

  echo ""
  echo "==> Applying AWS modules (IAM + SSM parameter placeholders)..."
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

main() {
  echo "Homelab bootstrap"
  echo "================="
  echo ""

  setup_hooks
  check_prerequisites
  bootstrap_aws_modules
  prompt_secrets
  full_apply

  echo ""
  echo "Bootstrap complete."
}

main "$@"
