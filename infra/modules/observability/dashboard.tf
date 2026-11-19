# Dashboard operativo: de afuera hacia adentro. Primero lo que ve el cliente (chequeo sintético, ALB),
# después los servicios (tareas, CPU, memoria, errores) y al final los datos (RDS, Redis).

locals {
  services = sort(keys(var.service_names))

  alarm_arns = concat(
    [aws_cloudwatch_metric_alarm.synthetic.arn, aws_cloudwatch_metric_alarm.alb_5xx.arn, aws_cloudwatch_metric_alarm.error_logs.arn],
    [for a in aws_cloudwatch_metric_alarm.unhealthy_targets : a.arn],
  )

  log_sources = join(" | ", [for g in values(var.log_group_names) : "SOURCE '${g}'"])

  widgets = [
    {
      type       = "alarm", x = 0, y = 0, width = 24, height = 3
      properties = { title = "Alarmas (${var.environment})", alarms = local.alarm_arns }
    },
    {
      type = "metric", x = 0, y = 3, width = 12, height = 6
      properties = {
        title  = "Chequeo sintético: éxito por chequeo (1 = ok)"
        region = var.aws_region, view = "timeSeries", stat = "Minimum", period = 300
        yAxis  = { left = { min = 0, max = 1 } }
        metrics = [for c in local.synthetic_checks :
        ["Tero/Synthetics", "Success", "Environment", var.environment, "Check", c, { label = c }]]
      }
    },
    {
      type = "metric", x = 12, y = 3, width = 12, height = 6
      properties = {
        title  = "Chequeo sintético: latencia (ms)"
        region = var.aws_region, view = "timeSeries", stat = "Average", period = 300
        metrics = [for c in local.synthetic_checks :
        ["Tero/Synthetics", "LatencyMs", "Environment", var.environment, "Check", c, { label = c }]]
      }
    },
    {
      type = "metric", x = 0, y = 9, width = 8, height = 6
      properties = {
        title  = "ALB: pedidos y errores"
        region = var.aws_region, view = "timeSeries", stat = "Sum", period = 60
        metrics = [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { label = "Pedidos" }],
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { label = "5xx de servicios" }],
          ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { label = "5xx del ALB" }],
          ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", var.alb_arn_suffix, { label = "4xx de servicios" }],
        ]
      }
    },
    {
      type = "metric", x = 8, y = 9, width = 8, height = 6
      properties = {
        title  = "Tiempo de respuesta p95 por servicio (s)"
        region = var.aws_region, view = "timeSeries", stat = "p95", period = 60
        metrics = [for k, tg in var.target_groups :
        ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", tg.load_balancer, "TargetGroup", tg.target_group, { label = k }]]
      }
    },
    {
      type = "metric", x = 16, y = 9, width = 8, height = 6
      properties = {
        title  = "Tareas sanas en el ALB por servicio"
        region = var.aws_region, view = "timeSeries", stat = "Minimum", period = 60
        metrics = [for k, tg in var.target_groups :
        ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", tg.load_balancer, "TargetGroup", tg.target_group, { label = k }]]
      }
    },
    {
      type = "metric", x = 0, y = 15, width = 8, height = 6
      properties = {
        title  = "ECS: tareas en ejecución"
        region = var.aws_region, view = "timeSeries", stat = "Minimum", period = 60
        metrics = [for s in local.services :
        ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.cluster_name, "ServiceName", var.service_names[s], { label = s }]]
      }
    },
    {
      type = "metric", x = 8, y = 15, width = 8, height = 6
      properties = {
        title  = "ECS: CPU por servicio (%)"
        region = var.aws_region, view = "timeSeries", stat = "Average", period = 60
        metrics = [for s in local.services :
        ["AWS/ECS", "CPUUtilization", "ClusterName", var.cluster_name, "ServiceName", var.service_names[s], { label = s }]]
      }
    },
    {
      type = "metric", x = 16, y = 15, width = 8, height = 6
      properties = {
        title  = "ECS: memoria por servicio (%)"
        region = var.aws_region, view = "timeSeries", stat = "Average", period = 60
        metrics = [for s in local.services :
        ["AWS/ECS", "MemoryUtilization", "ClusterName", var.cluster_name, "ServiceName", var.service_names[s], { label = s }]]
      }
    },
    {
      type = "metric", x = 0, y = 21, width = 12, height = 6
      properties = {
        title   = "Logs con level=error por servicio"
        region  = var.aws_region, view = "timeSeries", stat = "Sum", period = 300
        metrics = [for s in local.services : [local.error_namespace, s, { label = s }]]
      }
    },
    {
      type = "log", x = 12, y = 21, width = 12, height = 6
      properties = {
        title  = "Últimos errores (logs JSON)"
        region = var.aws_region, view = "table"
        query  = "${local.log_sources} | fields @timestamp, service, message, error_type, route, status | filter level = 'error' | sort @timestamp desc | limit 20"
      }
    },
    {
      type = "metric", x = 0, y = 27, width = 12, height = 6
      properties = {
        title  = "RDS PostgreSQL"
        region = var.aws_region, view = "timeSeries", stat = "Average", period = 300
        metrics = [
          ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_identifier, { label = "CPU (%)" }],
          ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_instance_identifier, { label = "Conexiones", yAxis = "right" }],
        ]
      }
    },
    {
      type = "metric", x = 12, y = 27, width = 12, height = 6
      properties = {
        title  = "ElastiCache Redis"
        region = var.aws_region, view = "timeSeries", stat = "Average", period = 300
        metrics = [
          ["AWS/ElastiCache", "EngineCPUUtilization", "CacheClusterId", var.redis_cache_cluster_id, { label = "CPU del motor (%)" }],
          ["AWS/ElastiCache", "CurrConnections", "CacheClusterId", var.redis_cache_cluster_id, { label = "Conexiones", yAxis = "right" }],
        ]
      }
    },
  ]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.name_prefix}-operacion"
  dashboard_body = jsonencode({ widgets = local.widgets })
}
