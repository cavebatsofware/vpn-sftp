resource "aws_cloudwatch_log_group" "application_logs" {
  name              = "/aws/infrastructure/${var.environment}"
  retention_in_days = var.log_retention_days
}

resource "aws_sns_topic" "alerts" { name = "${var.project_name}-${var.environment}-alerts" }

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "sftp_cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-sftp-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  dimensions          = { InstanceId = var.sftp_instance_id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "vpn_packets_in_low" {
  alarm_name          = "${var.project_name}-${var.environment}-vpn-packets-in-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "NetworkPacketsIn"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  dimensions          = { InstanceId = var.vpn_instance_id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

output "alerts_topic_arn" { value = aws_sns_topic.alerts.arn }
