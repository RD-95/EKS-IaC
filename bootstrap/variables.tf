variable "bucket_name" {
  description = "S3 bucket name for Terraform state (must be globally unique)"
  type        = string
  default     = "eks-iac-tfstate-rd95"
}
