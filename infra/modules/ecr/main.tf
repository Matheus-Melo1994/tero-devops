# Un repositorio ECR por microservicio (punto 3.2: registry). Compartido entre ambientes:
# la misma imagen (por SHA) se promueve de Dev a Test a Prod sin reconstruir.

resource "aws_ecr_repository" "this" {
  for_each = toset(var.services)

  name                 = "${var.name_prefix}-${each.key}"
  image_tag_mutability = "MUTABLE"

  # Escaneo de vulnerabilidades al hacer push (complementa a Trivy en el pipeline).
  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Política de retención: conservar las últimas 10 imágenes, borrar el resto (contiene costo).
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Conservar las ultimas 10 imagenes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
