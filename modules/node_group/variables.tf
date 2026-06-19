variable "cluster_name" {
  description = "EKS cluster name to attach this node group to"
  type        = string
}

variable "node_role_arn" {
  description = "IAM role ARN for the worker nodes"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs where nodes will be placed"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.micro"
}

variable "desired_size" {
  type    = number
  default = 2
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 3
}
