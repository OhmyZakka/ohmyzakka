#!/bin/bash
#MySQL Backup Scripts
backupdir=/data/mysql/backup
user=root
port=3306
password=password
#host=127.0.0.1
host=127.0.0.1
file=increment

echo "backup start" `date` >> $backupdir/backup_history.log

case `date +%u` in
  1) echo "logic full backup" >>$backupdir/backup_history.log
        mysqldump --all-databases -u$user -p$password -h$host -P$port --single-transaction -q  | gzip > $backupdir/bak_`date +%Y%m%d%H%M%S`.zip
        ;;
  2) echo "physical full backup" >> $backupdir/backup_history.log
        innobackupex --defaults-file=/etc/my.cnf --user=$user --password=$passwd   $backupdir
        ;;
  3) echo "physical increment backup"  >> $backupdir/backup_history.log
        innobackupex  --defaults-file=/etc/my.cnf  --user=$user --password=$passwd  --incremental --incremental-basedir=$backupdir/$file_`date +%Y%m%d%H%M%S`.dmp   $backupdir/$file_`date +%Y%m%d%H%M%S`.log
        ;;
  4) echo "physical increment backup"  >> $backupdir/backup_history.log
        innobackupex  --defaults-file=/etc/my.cnf  --user=$user --password=$passwd  --incremental --incremental-basedir=$backupdir/$file_`date +%Y%m%d%H%M%S`.dmp   $backupdir/$file_`date +%Y%m%d%H%M%S`.log
        ;;
  5) ehco "physical full backup"  >> $backupdir/backup_history.log
        innobackupex --defaults-file=/etc/my.cnf --user=$user --password=$passwd   $backupdir
        ;;
  6) echo "physical increment backup"  >> $backupdir/backup_history.log
        innobackupex  --defaults-file=/etc/my.cnf  --user=$user --password=$passwd  --incremental --incremental-basedir=$backupdir/$file_`date +%Y%m%d%H%M%S`.dmp   $backupdir/$file_`date +%Y%m%d%H%M%S`.log
        ;;
  7) echo "physical increment backup"  >> $backupdir/backup_history.log
        innobackupex  --defaults-file=/etc/my.cnf  --user=$user --password=$passwd  --incremental --incremental-basedir=$backupdir/$file_`date +%Y%m%d%H%M%S`.dmp   $backupdir/$file_`date +%Y%m%d%H%M%S`.log
        ;;
  *) echo "error" >> $backupdir/backup_history.log
        ;;
