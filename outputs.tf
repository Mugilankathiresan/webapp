output "alb_dns" {
  description = "ALB DNS name"
  value       = aws_lb.alb.dns_name
}

output "asg_name" {
  value = aws_autoscaling_group.web_asg.name
}

output "s3_artifact_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}
