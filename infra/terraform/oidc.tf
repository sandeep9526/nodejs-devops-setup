variable "github_owner" {
  description = "GitHub organization or user that owns the repository"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "github_branch" {
  description = "Branch allowed to deploy to AWS"
  type        = string
  default     = "main"
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  # AWS manages the trusted TLS certificate chain.
  # Do not add a manually copied thumbprint unless AWS requires it.
}

data "aws_iam_policy_document" "github_oidc_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${var.github_branch}"
      ]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name                 = "github-actions-production-deploy"
  assume_role_policy   = data.aws_iam_policy_document.github_oidc_assume_role.json
  max_session_duration = 3600

  tags = {
    ManagedBy   = "Terraform"
    Environment = "production"
  }
}

output "github_deploy_role_arn" {
  description = "IAM role assumed by the authorized GitHub Actions workflow"
  value       = aws_iam_role.github_deploy.arn
}
