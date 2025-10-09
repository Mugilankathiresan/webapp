#!/bin/bash
# userdata for Amazon Linux 2: install nginx, CodeDeploy agent, create index
set -e
yum update -y
yum install -y nginx ruby wget
systemctl enable nginx
systemctl start nginx

# put a distinctive index page
echo "<html><body><h2>Hello from $(hostname -f)</h2><p>Deployed by Terraform/CodeDeploy</p></body></html>" > /usr/share/nginx/html/index.html

# Install CodeDeploy agent (region-specific S3 URL)
REGION="us-east-1"
cd /tmp
if ! curl -sS https://aws-codedeploy-${REGION}.s3.${REGION}.amazonaws.com/latest/install -o install; then
  curl -sS https://aws-codedeploy-${REGION}.s3.amazonaws.com/latest/install -o install || true
fi
chmod +x ./install || true
./install auto || true
systemctl enable codedeploy-agent || true
systemctl start codedeploy-agent || true
