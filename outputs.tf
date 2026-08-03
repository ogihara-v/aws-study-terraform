output "alb_dns_name" {
  description = "ALBのDNS名(アクセス確認用)"
  value       = aws_lb.main.dns_name
}

output "rds_instance_endpoint" {
  description = "DB接続用のRDSエンドポイント"
  value = aws_db_instance.main.endpoint
}

output "alarm_topic_arn" {
  description = "SNSトピックARN(購読確認・追加購読用)"
  value = aws_sns_topic.alarm_topic.arn
}

output "ec2_public_ip" {
  description = "Ec2のパブリックIPアドレス(SSH接続確認用)"
  value = aws_instance.web.public_ip
}