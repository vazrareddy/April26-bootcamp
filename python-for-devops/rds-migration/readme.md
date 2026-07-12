user: postgres
password: Admin1234
db: rdsmigration

{"db_link":"postgres://postgres:Admin1234@rdsmigration.cvik8accw2tk.ap-south-1.rds.amazonaws.com:5432/rdsmigration"}

host: rdsmigration

```bash
export PGHOST="rdsmigration.cvik8accw2tk.ap-south-1.rds.amazonaws.com"
export PGPORT="5432"
export PGDATABASE="rdsmigration"
export PGUSER="postgres"
export PGPASSWORD="Admin1234"

```

RDS Migration automation strategy
0: use the event data to figure out details

1. fetch the rds database details -> boto3 -> rds -> get dbinstance details

2. use these deatils to create new rds instace with small storage. -
-> get db details, and password + figure out storage (or get that as input )

a few more things
-> befroe the data copy start -> wait for db to start to start
-> wait loop and kill switch 


rdsmigration.cvik8accw2tk.ap-south-1.rds.amazonaws.com
--> rdsmigration-old.cvik8accw2tk.ap-south-1.rds.amazonaws.com


rdsmigration-new.cvik8accw2tk.ap-south-1.rds.amazonaws.com
--> rdsmigration.cvik8accw2tk.ap-south-1.rds.amazonaws.com



3. ->  use pgsync to copy the data from old to new
- find out both endpoints for db and generate a config file
-  my db has a sg  and my ecs also has 


4. swap the names and stop the old one