output "dashboard_name" {
  description = "Dashboard operativo del ambiente en CloudWatch."
  value       = aws_cloudwatch_dashboard.this.dashboard_name
}

output "alarm_topic_arn" {
  description = "Tópico SNS al que avisan las alarmas."
  value       = aws_sns_topic.alarms.arn
}

output "alarm_names" {
  description = "Alarmas del ambiente."
  value = concat(
    [aws_cloudwatch_metric_alarm.synthetic.alarm_name, aws_cloudwatch_metric_alarm.alb_5xx.alarm_name, aws_cloudwatch_metric_alarm.error_logs.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.unhealthy_targets : a.alarm_name],
  )
}

output "synthetic_function_name" {
  description = "Lambda del chequeo sintético; se puede invocar a mano para probarla."
  value       = aws_lambda_function.synthetic.function_name
}
