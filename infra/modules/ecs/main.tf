# Orquestación (punto 3.3): cluster ECS Fargate, ALB público para ui y admin, un servicio por microservicio
# en subnets privadas, descubrimiento por nombre (Cloud Map) y logs JSON a CloudWatch (punto 8.2).

locals {
  public_services = { for k, s in var.services : k => s if s.public }
}

# ---------- Cluster ----------
resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled" # métricas de CPU/memoria por servicio para el dashboard (punto 8.1)
  }
}

# ---------- Descubrimiento de servicios: catalog.tero.local, orders.tero.local, etc. ----------
resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = "${var.environment}.tero.local"
  description = "Nombres internos de los microservicios de Tero (${var.environment})"
  vpc         = var.vpc_id
}

resource "aws_service_discovery_service" "this" {
  for_each = var.services

  name = each.key

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

# ---------- Logs: un grupo por servicio, JSON ya viene de la app ----------
resource "aws_cloudwatch_log_group" "this" {
  for_each = var.services

  name              = "/ecs/${var.name_prefix}/${each.key}"
  retention_in_days = var.log_retention_days
}

# ---------- IAM ----------
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Rol de ejecución: lo usa ECS para bajar la imagen, escribir logs y leer secretos al arrancar la tarea.
resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "execution_base" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

locals {
  db_init_secrets = var.db_init == null ? {} : var.db_init.secrets
  secret_arns     = distinct(concat(flatten([for s in var.services : values(s.secrets)]), values(local.db_init_secrets)))

  # Se decide por los nombres de las variables (conocidos al planificar), no por los ARN (recién se conocen al aplicar).
  has_secrets = length(local.db_init_secrets) > 0 || anytrue([for s in var.services : length(s.secrets) > 0])
}

resource "aws_iam_role_policy" "execution_secrets" {
  count = local.has_secrets ? 1 : 0

  name = "${var.name_prefix}-ecs-read-secrets"
  role = aws_iam_role.execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = local.secret_arns
    }]
  })
}

# Rol de tarea: lo usa la app en runtime. Hoy sin permisos; se amplía si un servicio necesita llamar a AWS.
resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

# ---------- ALB público ----------
resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_target_group" "public" {
  for_each = local.public_services

  name        = "${var.name_prefix}-${each.key}"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 15
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  # Por defecto va a ui; admin se enruta por path abajo.
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public["ui"].arn
  }
}

resource "aws_lb_listener_rule" "by_path" {
  for_each = { for k, s in local.public_services : k => s if s.path != "/" }

  listener_arn = aws_lb_listener.http.arn
  priority     = 10 + index(keys(local.public_services), each.key)

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public[each.key].arn
  }

  condition {
    path_pattern {
      values = concat([each.value.path, "${each.value.path}/*"], each.value.extra_paths)
    }
  }
}

# ---------- Task definitions ----------
locals {
  # Contenedor previo de los servicios que usan Postgres: corre el script idempotente y termina.
  # El servicio solo arranca si salió bien (dependsOn SUCCESS), así nunca encuentra su base sin crear.
  db_init_container = var.db_init == null ? null : {
    name      = "db-init"
    image     = var.db_init.image
    essential = false
    command   = ["sh", "-c", "printf '%s' \"$INIT_SQL\" | psql --no-psqlrc -v ON_ERROR_STOP=1"]

    environment = concat(
      [for k, v in var.db_init.environment : { name = k, value = v }],
      [{ name = "INIT_SQL", value = var.db_init.sql }]
    )
    secrets = [for k, arn in var.db_init.secrets : { name = k, valueFrom = arn }]
  }
}

resource "aws_ecs_task_definition" "this" {
  for_each = var.services

  family                   = "${var.name_prefix}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode(concat(
    each.value.db_init ? [merge(local.db_init_container, {
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this[each.key].name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "db-init"
        }
      }
    })] : [],
    [{
      name      = each.key
      image     = "${each.value.image}:${var.image_tag}"
      essential = true

      portMappings = [{ containerPort = 8080, protocol = "tcp" }]

      environment = [for k, v in each.value.environment : { name = k, value = v }]
      secrets     = [for k, arn in each.value.secrets : { name = k, valueFrom = arn }]

      dependsOn = each.value.db_init ? [{ containerName = "db-init", condition = "SUCCESS" }] : []

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this[each.key].name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = each.key
        }
      }

      # No-root ya viene del Dockerfile; readonly filesystem como defensa extra.
      readonlyRootFilesystem = false
    }]
  ))

  lifecycle {
    precondition {
      condition     = !each.value.db_init || var.db_init != null
      error_message = "El servicio ${each.key} pide db_init pero el módulo no recibió la variable db_init."
    }
  }
}

# ---------- Servicios ----------
resource "aws_ecs_service" "this" {
  for_each = var.services

  name            = each.key
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this[each.key].arn
  desired_count   = each.value.desired
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.services_security_group_id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.this[each.key].arn
  }

  dynamic "load_balancer" {
    for_each = each.value.public ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.public[each.key].arn
      container_name   = each.key
      container_port   = 8080
    }
  }

  # Rollback automático si el deploy nuevo no pasa el health check (demo de "rollback" para la defensa).
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener.http]

  lifecycle {
    # El pipeline actualiza la task definition; Terraform no debe revertirla.
    ignore_changes = [task_definition]
  }
}
