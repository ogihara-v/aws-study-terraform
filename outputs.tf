output "alb_dns_name" {
  description = "ALBのDNS名(アクセス確認用)"
  value       = aws_alb.main.dns_name
}

output "rds_instance_endpoint" {
  description = "DB接続用のRDSエンドポイント"
  value = aws_db_instance.main.endpoint
}

output "alarm_topic_arn" {
  description = "SNSトピックARN(購買確認・追加購読用)"
  value = aws_sns_topic.alarm_topic.arn
}