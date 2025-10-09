# Terraform HA Web App + CI/CD demo

Region: us-east-1

This package contains:
- Terraform files to create: VPC, ALB, AutoScaling Group (multi-AZ), EC2 launch template with userdata, S3 artifact bucket, IAM roles, CodeBuild, CodeDeploy, CodePipeline.
- Sample app files (appspec.yml, buildspec.yml, scripts/) to push to your GitHub repo so CodePipeline can build and deploy.

**Important — before running**
1. Create or choose an existing EC2 key pair name in **us-east-1** and set it in `terraform.tfvars` (see below).
2. Create `terraform.tfvars` file (example provided) and **fill** GitHub variables and optionally key_name.
3. Ensure your AWS credentials are available (environment variables or shared credentials) where you run `terraform`.

Example `terraform.tfvars`:
```
region = "us-east-1"
key_name = ""
my_ip_cidr = "YOUR_IP/32"
github_owner = "your-github-username-or-org"
github_repo_name = "your-repo-name"
github_branch = "main"
github_oauth_token = "ghp_...yourtoken..."
project_prefix = "tfdemo"
```

**To run**
```bash
cd terraform_project
terraform init
terraform apply
```

**Notes**
- The repo defaults in variables are empty. Fill GitHub details and token to allow CodePipeline to connect.
- IAM roles in this demo use broad managed policies for simplicity — tighten to least privilege in production.
- If you want a Node.js app instead of the static sample, replace `index.html` and buildspec accordingly.
