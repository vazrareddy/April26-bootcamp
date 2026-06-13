
# rds subnet group
resource "aws_kms_key" "rds_kms" {
  count                   = var.environment == "prod" ? 1 : 0
  description             = "KMS key for RDS cluster encryption"
  deletion_window_in_days = 7
}

resource "aws_db_subnet_group" "this" {
  name        = "${var.environment}-${var.prefix}-${var.project}-rds"
  description = "Subnet group for rds instance"
  subnet_ids  = module.network.private_subnet_ids
}

resource "random_password" "rds_password" {
  length           = 16
  special          = false
  override_special = "asdfgjhkqwrtopASHLSGSAGNAX12345667890"
}

resource "aws_db_instance" "postgres" {
 count = var.environment != "prod" ? 1 : 0
  identifier              = "${var.environment}-${var.prefix}-${var.project}-rds-instance"
  engine                  = "postgres"
  engine_version          = "14.23"
  instance_class          = "db.t3.micro"
  username                = "postgres"
  password                = random_password.rds_password.result
  db_name                 = "mydb"
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  publicly_accessible     = false
  backup_retention_period = 7
  allocated_storage       = 20
  skip_final_snapshot     = true
  apply_immediately =  true

}

# aws secret manager for rds password

resource "aws_secretsmanager_secret" "rds_password" {
  name        = "${var.environment}-${var.prefix}-${var.project}-rds-password"
  description = "Password for rds instance"
}

# aws secret manager version for rds password

resource "aws_secretsmanager_secret_version" "rds_password" {
  secret_id = aws_secretsmanager_secret.rds_password.id
  # db_link = "postgresql://{user}:{password}@{host}:{port}/{database_name}"
  secret_string =  var.environment == "prod" ? "postgresql://${aws_rds_cluster.postgres[0].master_username}:${random_password.rds_password.result}@${aws_rds_cluster.postgres[0].endpoint}:${aws_rds_cluster.postgres[0].port}/${aws_rds_cluster.postgres[0].database_name}" : "postgresql://${aws_db_instance.postgres[0].username}:${random_password.rds_password.result}@${aws_db_instance.postgres[0].address}:${aws_db_instance.postgres[0].port}/${aws_db_instance.postgres[0].db_name}"
}


# rds aurora postgres cluser
# read instace
# write instance

# RDS cluster for non-dev environments
resource "aws_rds_cluster" "postgres" {
  count                   = var.environment == "prod" ? 1 : 0
  cluster_identifier      = "${var.environment}-${var.prefix}-${var.project}-rds-cluster"
  engine                  = "aurora-postgresql"
  engine_version          = "14.22"
  master_username         = "postgres"
  master_password         = random_password.rds_password.result
  database_name           = "mydb"
  backup_retention_period = 7
  preferred_backup_window = "07:00-09:00"
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.this.name
  storage_encrypted       = true
  kms_key_id              = aws_kms_key.rds_kms[0].arn

  tags = {
    environment = var.environment
  }
}

resource "aws_rds_cluster_instance" "postgres_writer" {
  count                = var.environment == "prod" ? 1 : 0
  identifier           = "${var.environment}-${var.prefix}-${var.project}-rds-cluster-writer"
  cluster_identifier   = aws_rds_cluster.postgres[0].id
  # instance_class       = lookup(local.db_data, "instance_class", var.db_default_settings.instance_class)
  instance_class = "db.r5.large"
  engine               = aws_rds_cluster.postgres[0].engine
  engine_version       = aws_rds_cluster.postgres[0].engine_version
  publicly_accessible  = false
  db_subnet_group_name = aws_db_subnet_group.this.name
  ca_cert_identifier   = "rds-ca-rsa2048-g1"
  apply_immediately    = true

  tags = {
    environment = var.environment
  }
}

resource "aws_rds_cluster_instance" "postgres_reader" {
  count                = var.environment == "prod" ? 1 : 0
  identifier           = "${var.environment}-${var.prefix}-${var.project}-rds-cluster-reader"
  cluster_identifier   = aws_rds_cluster.postgres[0].id
  # instance_class       = lookup(local.db_data, "instance_class", var.db_default_settings.instance_class)
  instance_class = "db.r5.large"
  engine               = aws_rds_cluster.postgres[0].engine
  engine_version       = aws_rds_cluster.postgres[0].engine_version
  publicly_accessible  = false
  db_subnet_group_name = aws_db_subnet_group.this.name
  ca_cert_identifier   = "rds-ca-rsa2048-g1"
  apply_immediately    = true

  tags = {
    environment = var.environment
  }
}
