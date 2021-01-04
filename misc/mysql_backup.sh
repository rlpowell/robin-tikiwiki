#!/bin/bash

exec 2>&1
set -e
set -x

#********************
# Tiki-Specific Cleanup
#********************

mysql tiki_robin -e 'delete from sessions where expiry < UNIX_TIMESTAMP();'

mysql tiki_robin -e 'truncate tiki_stats;'

mysql tiki_robin -e 'delete from tiki_actionlog where lastmodif < UNIX_TIMESTAMP(CURRENT_DATE() - INTERVAL 6 MONTH);'

#********************
# MySQL cleanup
#********************

# Only do the big jobs once a month
if [ "$(date +%-d)" -eq 1 ]
then
  # Repairs brokenness
  /usr/bin/mysqlcheck --all-databases --auto-repair | egrep -v '(Table is already up to date| OK)$'

  # defragments after large deletes or whatever
  /usr/bin/mysqlcheck --all-databases --optimize | egrep -v '(Table is already up to date| OK|mysql.general_log|mysql.slow_log|note *: The storage engine for the table doesn.t support optimize)$'
fi

# updates keys/indexes for speed
/usr/bin/mysqlcheck --all-databases --analyze | egrep -v '(Table is already up to date| OK|mysql.general_log|mysql.slow_log|note *: The storage engine for the table doesn.t support analyze)$' || true

#********************
# MySQL backup
#********************

mkdir -p /var/lib/mysql/backups
chmod 700 /var/lib/mysql/backups
cd /var/lib/mysql/backups
ls -l

# Delete old backups
ls -1rt | head -n -40 | xargs rm -f -v

for database in $(mysql -N -B -e 'show databases;' | grep -v information_schema | grep -v performance_schema)
do
  DATESTR=$(date +%Y%b%d)

  echo "Backing up MySQL database $database"
  /bin/rm -f $database.$DATESTR.gz
  /usr/bin/mysqldump --opt --single-transaction --skip-triggers --add-drop-database \
    --databases $database | /bin/gzip --rsyncable -9 >$database.$DATESTR.gz
  echo "Done backing up MySQL database $database"
done
