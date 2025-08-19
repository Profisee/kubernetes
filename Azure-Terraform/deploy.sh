#!/bin/bash
set -e

echo "========================================"
echo "  Profisee Platform Terraform Deployment"
echo "========================================"
echo

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo "ERROR: terraform.tfvars not found!"
    echo
    echo "Please copy sample.tfvars to terraform.tfvars and customize it:"
    echo "  cp sample.tfvars terraform.tfvars"
    echo
    exit 1
fi

echo "[INFO] Initializing Terraform..."
terraform init

echo
echo "[INFO] Planning deployment..."
terraform plan

echo
read -p "Do you want to proceed with deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

echo
echo "[INFO] Applying Terraform configuration..."
terraform apply -auto-approve

echo
echo "========================================"
echo "  Deployment Complete!"
echo "========================================"
echo
echo "View deployment info:"
echo "  terraform output deployment_summary"
echo
echo "Next steps:"
echo "  terraform output next_steps"
echo
