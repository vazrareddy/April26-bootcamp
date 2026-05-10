# we will use 2-tier app -> student portal

# build image and push to ecr

ecr repo : 879381241087.dkr.ecr.ap-south-1.amazonaws.com/april-ecs-2tier


docker build --platform linux/amd64 -t 879381241087.dkr.ecr.ap-south-1.amazonaws.com/april-ecs-2tier:1.0 .


aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin 879381241087.dkr.ecr.ap-south-1.amazonaws.com


docker push 879381241087.dkr.ecr.ap-south-1.amazonaws.com/april-ecs-2tier:1.0

ecs execution role -> create a role and attach AmazonECSTaskExecutionRolePolicy policy

if using db creds as secrets then attach AWSSecretsManagerClientReadOnlyAccess too


# postgres stuff
user postgres
password; postgres_pass
db_name: april
port 5432
host


DB_LINK = "postgresql://postgres:postgres_pass@april2ier.cvisdfgw2tk.ap-south-1.rds.amazonaws.com:5432/april"