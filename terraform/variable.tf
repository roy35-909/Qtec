variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Used to name all resources"
  type        = string
  default     = "qtec-devops"
}

variable "instance_type" {
  description = "EC2 instance size"
  type        = string
  default     = "t2.micro"
}

variable "ami_id" {
  description = "Ubuntu 24.04 LTS AMI ID"
  type        = string
  default     = "ami-0df7a207adb9748c7"
}

variable "public_key_path" {
  description = "Path to your local SSH public key"
  type        = string
  default     = "~/.ssh/jvai.pub"
}

variable "allowed_ssh_cidr" {
  description = "Your IP address for SSH access "
  type        = string

}


variable "gh_token" {
  description = "GitHub personal access token to clone the repo"
  type        = string
  sensitive   = true
}

variable "github_repo" {
  description = "GitHub repo in format username/reponame"
  type        = string
  default     = "roy35-909/Qtec"
}

variable "grafana_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

variable "docker_username" {
  description = "Docker Hub username to pull images"
  type        = string
}