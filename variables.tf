variable "aws_region" {
  description = "リソースを作成するリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "リソース名の固定値"
  type        = string
  default     = "aws-study"
}

variable "key_name" {
  description = "EC2に設定するキーペアを選択"
  type        = string
  default     = "aws-study-tokyo"
}

variable "my_ip" {
  description = "SSH接続を許可する管理者のグローバルIP"
  type        = string
}

variable "vpc_cidr" {
  description = "VPCのIPアドレスを入力"
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_user" {
  description = "DBのマスターユーザ名"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "DBのマスターパスワード"
  type        = string
  sensitive   = true
}

variable "alarm_email" {
  description = "アラーム通知先のアドレス"
  type        = string
}