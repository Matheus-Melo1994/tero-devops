# Backend remoto (punto 7.2 de la letra): el estado vive en S3, con lock en DynamoDB
# para que dos applys simultáneos no se pisen.
# El bucket y la tabla son lo ÚNICO que se crea a mano (la letra lo permite): el estado
# no puede guardarse en un bucket que el propio estado administra.
#
# Para crearlos una vez (reemplazar <cuenta> por un sufijo único):
#   aws s3api create-bucket --bucket tero-tfstate-<cuenta> --region us-east-1
#   aws s3api put-bucket-versioning --bucket tero-tfstate-<cuenta> --versioning-configuration Status=Enabled
#   aws s3api put-bucket-encryption --bucket tero-tfstate-<cuenta> \
#     --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
#   aws dynamodb create-table --table-name tero-tfstate-lock \
#     --attribute-definitions AttributeName=LockID,AttributeType=S \
#     --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST
#
# Cada ambiente usa su propia key, así Dev/Test/Prod no comparten estado:
#   terraform init -backend-config="key=dev/terraform.tfstate"
terraform {
  backend "s3" {
    bucket         = "tero-tfstate-CAMBIAR"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tero-tfstate-lock"
    encrypt        = true
  }
}
