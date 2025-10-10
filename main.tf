terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {}

# --- Simple VPC + 2 public subnets (for demo) ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "tf-vpc" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 1)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "tf-public-${count.index}" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "tf-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "tf-public-rt" }
}

resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- Security Groups ---
resource "aws_security_group" "alb_sg" {
  name        = "tf-alb-sg"
  description = "Allow HTTP"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

egress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}
 }


resource "aws_security_group" "ec2_sg" {
  name        = "tf-ec2-sg"
  description = "Allow from ALB"
  vpc_id      = aws_vpc.main.id
  ingress {
    description      = "http from alb"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    security_groups  = [aws_security_group.alb_sg.id]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }
  
egress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}
 }


# --- ALB + Target Group + Listener ---
resource "aws_lb" "alb" {
  name               = "tf-alb"
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb_sg.id]
  tags = { Name = "tf-alb" }
}

resource "aws_lb_target_group" "web_tg" {
  name        = "tf-web-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  health_check {
    path                = "/"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  target_type = "instance"
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

# --- IAM for EC2 instances (to allow CodeDeploy agent + SSM) ---
resource "aws_iam_role" "ec2_role" {
  name = "tf-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_codedeploy_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforAWSCodeDeploy"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "tf-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

# --- AMI (Amazon Linux 2) ---
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# --- Launch Template + AutoScaling Group (multi-AZ) ---
resource "aws_launch_template" "web_lt" {
  name_prefix   = "tf-web-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2_sg.id]
  }

  user_data = base64encode(file("${path.module}/userdata.sh"))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "tf-web-instance"
      CodedeployGroup = "true"
    }
  }
}

resource "aws_autoscaling_group" "web_asg" {
  name                      = "tf-web-asg"
  desired_capacity          = var.asg_desired
  max_size                  = var.asg_max
  min_size                  = var.asg_min
  vpc_zone_identifier       = aws_subnet.public[*].id
  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.web_tg.arn]
  health_check_type = "ELB"
  health_check_grace_period = 120

  tag {
    key                 = "Name"
    value               = "tf-web-asg-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "CodeDeployGroup"
    value               = "true"
    propagate_at_launch = true
  }
}

# --- S3 bucket for pipeline artifacts ---
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "artifacts-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = {
    Name = "tf-artifacts"
  }
}

resource "aws_s3_bucket_ownership_controls" "ownership" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- IAM roles for CodeBuild, CodeDeploy, CodePipeline (demo uses AdministratorAccess for simplicity) ---
resource "aws_iam_role" "pipeline_role" {
  name = "tf-codepipeline-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect="Allow", Principal={ Service="codepipeline.amazonaws.com" }, Action="sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy_attachment" "pipeline_admin" {
  role       = aws_iam_role.pipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role" "codebuild_role" {
  name = "tf-codebuild-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect="Allow", Principal={ Service="codebuild.amazonaws.com" }, Action="sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy_attachment" "codebuild_admin" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role" "codedeploy_service_role" {
  name = "tf-codedeploy-service-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect="Allow", Principal={ Service="codedeploy.amazonaws.com" }, Action="sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy_attachment" "codedeploy_admin" {
  role       = aws_iam_role.codedeploy_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# --- CodeDeploy app and deployment group (select instances by tag) ---
resource "aws_codedeploy_app" "app" {
  name             = "${var.project_prefix}-codedeploy-app"
  compute_platform = "Server"
}

resource "aws_codedeploy_deployment_group" "deployment_group" {
  app_name              = aws_codedeploy_app.app.name
  deployment_group_name = "${var.project_prefix}-deployment-group"
  service_role_arn      = aws_iam_role.codedeploy_service_role.arn

  ec2_tag_set {
    ec2_tag_filter {
      key   = "CodeDeployGroup"
      type  = "KEY_AND_VALUE"
      value = "true"
    }
  }

  deployment_style {
    deployment_type   = "IN_PLACE"
    deployment_option = "WITHOUT_TRAFFIC_CONTROL"
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  depends_on = [aws_codedeploy_app.app]
}

# --- CodeBuild project (source & artifacts will be CODEPIPELINE) ---
resource "aws_codebuild_project" "project" {
  name          = "${var.project_prefix}-cb"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:5.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = false
  }

  source {
    type = "CODEPIPELINE"
  }

  badge_enabled = false
}

# --- CodePipeline connecting GitHub -> CodeBuild -> CodeDeploy ---
resource "aws_codepipeline" "pipeline" {
  name     = "${var.project_prefix}-pipeline"
  role_arn = aws_iam_role.pipeline_role.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.artifacts.bucket
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["source_output"]
      run_order        = 1

      configuration = {
        Owner      = var.github_owner
        Repo       = var.github_repo_name
        Branch     = var.github_branch
        OAuthToken = var.github_oauth_token
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      run_order        = 1

      configuration = {
        ProjectName = aws_codebuild_project.project.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy"
      version         = "1"
      input_artifacts = ["build_output"]
      run_order       = 1

      configuration = {
        ApplicationName     = aws_codedeploy_app.app.name
        DeploymentGroupName = aws_codedeploy_deployment_group.deployment_group.deployment_group_name
      }
    }
  }
}

new