variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "project" {
  description = "Short name used to prefix every resource"
  type        = string
  default     = "gxp"
}

variable "environment" {
  description = "Environment this stack represents"
  type        = string
  default     = "lab"
}

variable "owner" {
  description = "Tag applied to every resource so nothing is orphaned anonymously"
  type        = string
}

variable "cluster_version" {
  description = "EKS control plane version"
  type        = string
  default     = "1.30"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.42.0.0/16"
}

variable "node_instance_types" {
  description = "Graviton instances so images built on Apple Silicon run natively"
  type        = list(string)
  default     = ["t4g.medium"]
}

variable "node_desired_size" {
  description = "Desired managed node group size"
  type        = number
  default     = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "single_nat_gateway" {
  description = "One NAT gateway instead of one per AZ. False is more resilient and roughly triples the NAT bill."
  type        = bool
  default     = true
}
