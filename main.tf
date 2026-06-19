module "vpc" {
  source = "./modules/vpc"

  name            = "eks-vpc"
  cidr            = "10.0.0.0/16"
  azs             = ["us-east-1a", "us-east-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]
}

module "iam" {
  source       = "./modules/iam"
  cluster_name = "eks-cluster"
}

module "eks" {
  source = "./modules/eks"

  cluster_name       = "eks-cluster"
  cluster_version    = "1.31"
  cluster_role_arn   = module.iam.cluster_role_arn
  subnet_ids         = concat(module.vpc.private_subnet_ids, module.vpc.public_subnet_ids)
}
