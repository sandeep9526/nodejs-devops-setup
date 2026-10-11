
variable "deployment_instance_tag_value" {
  description = "Value of the DeploymentTarget EC2 instance tag"
  type        = string
  default     = "nodejs-api-production"
}

data "aws_iam_policy_document" "github_deploy_ssm" {
  statement {
    sid       = "SendDeploymentCommandsToTaggedInstance"
    effect    = "Allow"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}::document/AWS-RunShellScript"]
  }

  statement {
    sid    = "TargetOnlyDeploymentInstances"
    effect = "Allow"
    actions = [
      "ssm:SendCommand"
    ]

    resources = ["arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/DeploymentTarget"
      values   = [var.deployment_instance_tag_value]
    }
  }

  statement {
    sid    = "ReadCommandStatus"
    effect = "Allow"
    actions = [
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_deploy_ssm" {
  name   = "github-actions-ssm-deploy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy_ssm.json
}

resource "aws_iam_role" "ec2_ssm" {
  name = "nodejs-api-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    ManagedBy   = "Terraform"
    Environment = "production"
  }
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "nodejs-api-ec2-instance-profile"
  role = aws_iam_role.ec2_ssm.name
}

output "ec2_instance_profile_name" {
  description = "Instance profile attached to the production EC2 instance"
  value       = aws_iam_instance_profile.ec2.name
}