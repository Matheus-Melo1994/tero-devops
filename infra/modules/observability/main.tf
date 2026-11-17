# Observabilidad del ambiente (bloque 8): un chequeo sintético serverless, métricas de errores a partir de
# los logs JSON, alarmas con aviso por SNS y un dashboard operativo. El procedimiento de respuesta de cada
# alarma está en infra/README.md.

locals {
  synthetic_name   = "${var.name_prefix}-synthetic"
  error_namespace  = "Tero/Logs/${var.environment}"
  create_role      = var.iam_role_arn == null
  lambda_role_arn  = local.create_role ? aws_iam_role.synthetic[0].arn : var.iam_role_arn
  synthetic_checks = ["ui-health", "catalog-products", "admin-panel"]
}

# ---------- Aviso de alarmas ----------
resource "aws_sns_topic" "alarms" {
  name = "${var.name_prefix}-alarms"
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alarm_email == null ? 0 : 1

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ---------- Errores de aplicación a partir de los logs JSON ----------
# Cada servicio escribe {"level":"error",...}; el filtro cuenta esas líneas en una métrica por servicio
# (namespace Tero/Logs/<ambiente>, métrica = nombre del servicio). El contenedor db-init escribe texto
# plano en el mismo grupo y el filtro JSON lo ignora.
resource "aws_cloudwatch_log_metric_filter" "errors" {
  for_each = var.log_group_names

  name           = "${var.name_prefix}-${each.key}-errors"
  log_group_name = each.value
  pattern        = "{ $.level = \"error\" }"

  metric_transformation {
    name          = each.key
    namespace     = local.error_namespace
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

# ---------- Chequeo sintético (Lambda + EventBridge) ----------
data "archive_file" "synthetic" {
  type        = "zip"
  source_file = "${path.module}/lambda/synthetic.py"
  output_path = "${path.module}/build/synthetic.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  count = local.create_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "synthetic" {
  count = local.create_role ? 1 : 0

  name               = "${local.synthetic_name}-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume[0].json
}

resource "aws_iam_role_policy_attachment" "synthetic_logs" {
  count = local.create_role ? 1 : 0

  role       = aws_iam_role.synthetic[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "synthetic_metrics" {
  count = local.create_role ? 1 : 0

  name = "${local.synthetic_name}-put-metrics"
  role = aws_iam_role.synthetic[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["cloudwatch:PutMetricData"]
      Resource  = "*"
      Condition = { StringEquals = { "cloudwatch:namespace" = "Tero/Synthetics" } }
    }]
  })
}

resource "aws_cloudwatch_log_group" "synthetic" {
  name              = "/aws/lambda/${local.synthetic_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "synthetic" {
  function_name    = local.synthetic_name
  description      = "Chequeo sintetico de Tero (${var.environment}): ui, catalogo y admin a traves del ALB"
  role             = local.lambda_role_arn
  runtime          = "python3.12"
  handler          = "synthetic.handler"
  filename         = data.archive_file.synthetic.output_path
  source_code_hash = data.archive_file.synthetic.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      TARGET_BASE_URL  = var.alb_url
      TERO_ENVIRONMENT = var.environment
      METRIC_NAMESPACE = "Tero/Synthetics"
    }
  }

  depends_on = [aws_cloudwatch_log_group.synthetic, aws_iam_role_policy_attachment.synthetic_logs]
}

resource "aws_cloudwatch_event_rule" "synthetic" {
  name                = local.synthetic_name
  description         = "Ejecuta el chequeo sintetico de Tero (${var.environment})"
  schedule_expression = var.synthetic_schedule
}

resource "aws_cloudwatch_event_target" "synthetic" {
  rule = aws_cloudwatch_event_rule.synthetic.name
  arn  = aws_lambda_function.synthetic.arn
}

resource "aws_lambda_permission" "synthetic" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.synthetic.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.synthetic.arn
}

# ---------- Alarmas ----------
resource "aws_cloudwatch_metric_alarm" "synthetic" {
  alarm_name          = "${var.name_prefix}-synthetic-failing"
  alarm_description   = "Tero no responde desde Internet: un chequeo sintetico fallo dos veces seguidas (o no corrio). Ver infra/README.md, Alarmas."
  namespace           = "Tero/Synthetics"
  metric_name         = "AllChecksPassed"
  dimensions          = { Environment = var.environment }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.name_prefix}-alb-target-5xx"
  alarm_description   = "Los servicios detras del ALB devolvieron mas de ${var.alb_5xx_threshold} respuestas 5xx en 5 minutos. Ver infra/README.md, Alarmas."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alb_5xx_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  for_each = var.target_group_arn_suffixes

  alarm_name          = "${var.name_prefix}-${each.key}-no-healthy-targets"
  alarm_description   = "El ALB no tiene ninguna tarea sana de ${each.key} desde hace 3 minutos. Ver infra/README.md, Alarmas."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  dimensions          = { LoadBalancer = var.alb_arn_suffix, TargetGroup = each.value }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "error_logs" {
  alarm_name          = "${var.name_prefix}-application-errors"
  alarm_description   = "Los servicios escribieron mas de ${var.error_log_threshold} logs con level=error en 5 minutos. Ver infra/README.md, Alarmas."
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.error_log_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  metric_query {
    id          = "total"
    expression  = "SUM(METRICS())"
    label       = "Logs de error (todos los servicios)"
    return_data = true
  }

  dynamic "metric_query" {
    for_each = aws_cloudwatch_log_metric_filter.errors
    content {
      id = "e_${metric_query.key}"
      metric {
        namespace   = local.error_namespace
        metric_name = metric_query.key
        period      = 300
        stat        = "Sum"
      }
    }
  }
}
