variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_prefix" {
  description = "Prefix for resources"
  type        = string
  default     = "tfdemo"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "key_name" {
  type    = string
  default = "" # set your EC2 key pair name before apply
}

variable "my_ip_cidr" {
  description = "CIDR for your SSH (for demo restrict to your IP)"
  default     = "0.0.0.0/0"
}


variable "asg_min" {
  type    = number
  default = 2
}

variable "asg_max" { 
  type = number 
  default = 4
 }
variable "asg_desired" { 
  type = number
   default = 2
 }


variable "github_owner" {
  type    = string
  default = ""
}

variable "github_repo_name" {
  type    = string
  default = ""
}

variable "github_branch" {
  type    = string
  default = "main"
}
variable "github_oauth_token" {
  type      = string
  default   = ""
  sensitive = true
}
