output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = aws_lb.app.dns_name
}

output "blue_instance_id" {
  description = "BLUE EC2 instance ID"
  value       = aws_instance.blue.id
}

output "green_instance_id" {
  description = "GREEN EC2 instance ID"
  value       = aws_instance.green.id
}

output "blue_target_group_arn" {
  description = "BLUE target group ARN"
  value       = aws_lb_target_group.blue.arn
}

output "green_target_group_arn" {
  description = "GREEN target group ARN"
  value       = aws_lb_target_group.green.arn
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.app.repository_url
}