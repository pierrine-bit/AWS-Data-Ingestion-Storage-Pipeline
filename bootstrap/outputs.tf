output "github_actions_role_arn" {
  description = "ARN of the CDEM02 GitHub Actions OIDC role — add this as AWS_OIDC_ROLE_ARN in the CDEM02 repo's GitHub Secrets"
  value       = aws_iam_role.github_actions.arn
}
