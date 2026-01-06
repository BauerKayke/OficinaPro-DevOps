variable "aws_region" {
  description = "Região da AWS"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome do projeto (usado para encontrar a VPC e nomear recursos)"
  type        = string
  default     = "fiap-oficinapro-kb"
}

variable "lambda_name" {
  description = "Nome da função Lambda"
  type        = string
  default     = "oficinapro-auth-function"
}

# Caminho para o ZIP da Lambda.
# No pipeline, este arquivo será gerado pelo build do Go.
variable "lambda_zip_path" {
  description = "Caminho para o arquivo ZIP contendo o binário da Lambda"
  type        = string
  default     = "function.zip"
}

# Variáveis de Ambiente para a Lambda

variable "db_user" {
  description = "Usuário do banco de dados"
  type        = string
  default     = "oficinapro_user"
}

variable "db_password" {
  description = "Senha do banco de dados"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Nome do banco de dados"
  type        = string
  default     = "oficinapro"
}

variable "jwt_secret" {
  description = "Segredo para assinatura do JWT"
  type        = string
  sensitive   = true
}

# --- TELEMETRY / OBSERVABILITY (OpenTelemetry + New Relic) ---

variable "telemetry_enabled" {
  description = "Habilita OpenTelemetry"
  type        = bool
  default     = true
}

variable "telemetry_service_name" {
  description = "Nome do serviço no OpenTelemetry"
  type        = string
  default     = "oficinapro-auth"
}

variable "telemetry_service_version" {
  description = "Versão do serviço"
  type        = string
  default     = "1.0.0"
}

variable "new_relic_license_key" {
  description = "New Relic License Key para envio de telemetria"
  type        = string
  sensitive   = true
}

variable "new_relic_otlp_endpoint" {
  description = "Endpoint OTLP do New Relic (porta 443 HTTPS)"
  type        = string
  default     = "otlp.nr-data.net"  # Porta 443 implícita (HTTPS) - mesmo do Java
}

variable "telemetry_sample_rate" {
  description = "Taxa de amostragem de telemetria (0.0 a 1.0)"
  type        = number
  default     = 1.0
}

# --- NEW RELIC LAMBDA EXTENSION (Captura de Logs) ---

variable "newrelic_extension_enabled" {
  description = "Habilita New Relic Lambda Extension para captura de logs"
  type        = bool
  default     = true
}

variable "newrelic_account_id" {
  description = "New Relic Account ID (encontre em User Menu > API Keys)"
  type        = string
  default     = ""
}

