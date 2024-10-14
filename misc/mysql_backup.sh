#!/bin/bash

# Error trapping from https://gist.github.com/oldratlee/902ad9a398affca37bfcfab64612e7d1
__error_trapper() {
  local parent_lineno="$1"
  local code="$2"
  local commands="$3"
  echo "error exit status $code, at file $0 on or near line $parent_lineno: $commands"
}
trap '__error_trapper "${LINENO}/${BASH_LINENO}" "$?" "$BASH_COMMAND"' ERR

set -euE -o pipefail
shopt -s failglob

exec 2>&1
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
  /usr/bin/mysqlcheck --all-databases --auto-repair

  # defragments after large deletes or whatever
  /usr/bin/mysqlcheck --all-databases --optimize
fi

# updates keys/indexes for speed
/usr/bin/mysqlcheck --all-databases --analyze

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
