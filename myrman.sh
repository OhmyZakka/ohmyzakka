#!/bin/sh
# ****************************************************************************
# Filename:
#         myrman.sh
# Author:
#         jeff.dowa@gmail.com
# Function:
#         perform mysql backup
# Usage Example:
#         myrman.sh --help
#         myrman.sh --type full --logical --destination=/dump/full/
#		  myrman.sh --type full --logical --destination=remote 
#		  myrman.sh --type full --destination=/dump/full/
#		  myrman.sh --type incremental --accumulate --destination=/dump/full/
#		  
# ****************************************************************************
# Change History:
# --------------------------------------------------
# Init Development		jeff.dowa		2014-08-08
# ****************************************************************************
function loading_functions(){
    [ -f /root/bin/functions ] && source /root/bin/functions
    [ -f /etc/init.d/functions ] && source /etc/init.d/functions
}

function usage(){
	cat <<-EOF
	Usage Info:
	    `basename $0` [options]
	options as follows:
	    --help           Print help infomation. 
	    --type           Backup type: [full|incremental|binlog] supported, default is full.
	    --logical        Full logical dump.
	    --accumulate     Perform accumulate incremental backup. 
	    --destination    Backup destination, can be remote, which is backup center. 
	    --remote-user    When destination is remote, it specifies the remote user.
	    --remote-host    When destination is remote, it specifies the remote host.
	    --remote-dir     When destination is remote, it specifies the remote directory.
	    --high-perf      High Performance mode, compression and parallel backup.
	    --stream         Streaming Backup
	    --host           Hostname, default 127.0.0.1
	    --port           Port number, default 3306.
	    --user           User name.
	    --password       Password.
	EOF
}

function loading_default_settings(){
	MYSQL_BASE=/opt/mysql
	MYSQL_HOME=${MYSQL_BASE}
	MYSQL_TOOL_HOME=/usr
    MYSQL_USER=dump
    MYSQL_HOST=127.0.0.1
    MYSQL_PASSWD="abc#123"
    MYSQL_PORT=3306
}

function value_debug(){
    echo "**********************************************"
    echo MYSQL_USER=$MYSQL_USER
    echo MYSQL_HOST=$MYSQL_HOST
    echo MYSQL_PASSWD=$MYSQL_PASSWD
    echo MYSQL_PORT=$MYSQL_PORT
	echo "*********************"
	echo DUMP_TYPE=$DUMP_TYPE
	echo LOGICAL_DUMP=$LOGICAL_DUMP
	echo ACCUMULATE_DUMP=$ACCUMULATE_DUMP
	echo DUMP_DESTINATION=$DUMP_DESTINATION
    echo "**********************************************"
}

function mysql_detect(){
    [ `lsof -i ":$MYSQL_PORT" | grep mysql | wc -l` -eq 0 ] && {
        action "[*ERROR*] MySQL is not started on port $MYSQL_PORT!" /bin/false
        exit 0
    }
}

function loading_mysql_config_file(){
	basedir=${MYSQL_BASE}
	port=${MYSQL_PORT}
	datadir=$basedir/data/${port}

    [ -n "$basedir" ] && {
        if [ -r "${basedir}/data/conf/my${port}.cnf" ]
          then
            mysql_config_file="${basedir}/data/conf/my${port}.cnf"
        elif [ -r "${basedir}/my.cnf" ]
          then
            mysql_config_file="${basedir}/my.cnf"
        elif [ -r "/etc/my.cnf" ]
          then
            mysql_config_file="/etc/my.cnf"
        fi
    } || {
        [ -n "${datadir}" ] && {
            cd ${datadir} && cd .. && tmp=`pwd`
            if [ -r "${tmp}/conf/my${port}.cnf" ]
              then
                    mysql_config_file="${tmp}/conf/my${port}.cnf"
			else
				cd .. && tmp=`pwd`
				[ -r "${tmp}/my.cnf" ] && {
					mysql_config_file=${tmp}/my.cnf
				} || {
					[ -r "/etc/my.cnf" ] && mysql_config_file="/etc/my.cnf"
				}
            fi
        } || {
            log_failure_msg "[*ERROR*]: MySQL basedir or datadir must be specified."
            exit 1
        }
    }
}


function full_dump_mysqldump(){
	[ -x ${MYSQL_TOOL_HOME}/bin/mysqldump ] && {
		DUMP_CMD="${MYSQL_TOOL_HOME}/bin/mysqldump"
	} || {
		[ -x $MYSQL_HOME/bin/mysqldump ] && {
			DUMP_CMD="${MYSQL_HOME}/bin/mysqldump"
		} || {
			action "[*ERROR*] Couldn't find mysqldump." /bin/false
			exit 1
		} 
	}
	
	DUMP_CMD="$DUMP_CMD --defaults-file=${mysql_config_file}" 
	DUMP_CMD="$DUMP_CMD --host=${MYSQL_HOST} --port=${MYSQL_PORT} --user=${MYSQL_USER} --password=\"${MYSQL_PASSWD}\""
	DUMP_CMD="$DUMP_CMD --all-databases --flush-logs --lock-all-tables --master-data=2 --extended-insert --quick"
		
	[ "$DUMP_DESTINATION" = "remote" ] && {
		now=`date +%Y_%m_%d_%H_%M_%S`
		REMOTE_FILE=$REMOTE_DIR/`hostname`_${now}.tar.gz
		export PATH=${PATH}:/usr/local/sbin:/usr/local/bin:/root/bin 
		which pv > /dev/null 2>&1
		RETVAL=$?
		[ $RETVAL -gt 0 ] && {
			action "[*ERROR*] Please install and configure PV tool." /bin/false
			exit 1	
		}
		DUMP_CMD="$DUMP_CMD 2>/dev/null | gzip - | pv -q -L 1M | ssh $DUMP_REMOTELY \"cat - > $REMOTE_FILE\"" 
		echo "Starting remote logical full dump."
		start_time=`date "+%F %H:%M:%S"`
		eval "$DUMP_CMD"
		[ $? -eq 0 ] && {
			DESTINATION="${DUMP_REMOTELY}:${REMOTE_FILE}"
			end_time=`date "+%F %H:%M:%S"`
			size=`ssh $DUMP_REMOTELY "ls -lh $REMOTE_FILE" | cut -d " " -f 5`
			logging_in_db "Full" "Logical" "$DESTINATION" "Succeed" "$start_time" "$end_time" "$size" "" "" ""
			action "[*INFO*] Remote full logical dump completed successfully." /bin/true
            exit 0	
		} || {
			end_time=`date "+%F %H:%M:%S"`
			logging_in_db "Full" "Logical" "$DUMP_REMOTELY" "Failed" "" "$start_time" "$end_time" "" "" "" ""
			action "[*ERROR*] Failed to do remote logical dump." /bin/false
            exit 1
		}
	} || {
		now=`date +%Y_%m_%d_%H_%M_%S`	
		errorlog=${DUMP_DESTINATION}/`hostname`_${now}.error
		DUMP_FILE=${DUMP_DESTINATION}/`hostname`_${now}.sql
		DUMP_CMD="$DUMP_CMD > ${DUMP_FILE} 2> $errorlog" 
		echo "Starting full logical dump."
		start_time=`date "+%F %H:%M:%S"`
		eval "$DUMP_CMD"
		[ $? -eq 0 ] && {
			end_time=`date "+%F %H:%M:%S"`
			size=`ls -lh ${DUMP_FILE} | awk '{printf("%s",$5)}'`
			if [ `head -n 100 ${DUMP_FILE} | grep -i "CHANGE MASTER TO" | wc -l` -eq 1 ]
			  then
				binlog_info=`head -n 100 ${DUMP_FILE} | grep -i "CHANGE MASTER TO" | cut -d " " -f 5-6`
			elif [ `head -n 1000 ${DUMP_FILE} | grep -i "CHANGE MASTER TO" | wc -l` -eq 1 ]
			  then
				binlog_info=`head -n 1000 ${DUMP_FILE} | grep -i "CHANGE MASTER TO" | cut -d " " -f 5-6`
			else
				echo "[*WARNING*] Binlog position is not dumped by mysqldump."
			fi 
			binlog=`echo $binlog_info | cut -d , -f 1 | cut -d = -f 2 | awk -F"'" '{print $2}'`
			binlog_pos=`echo $binlog_info | cut -d , -f 2 | cut -d = -f 2 | awk -F";" '{print $1}'`
			[ -f $errorlog ] && rm -rf $errorlog
			logging_in_db "Full" "Logical" "$DUMP_FILE" "Succeed" "$start_time" "$end_time" "$size" "$binlog" "$binlog_pos" ""
			action "[*INFO*] Full Logical dump completed successfully." /bin/true
			exit 0
		} || {
			end_time=`date "+%F %H:%M:%S"`
			size=`ls -lh ${DUMP_FILE} | awk '{printf("%s",$5)}'`
			logging_in_db "Full" "Logical" "$DUMP_FILE" "Failed" "$start_time" "$end_time" "$size" "" "" "$errorlog"
			action "[*ERROR*] Failed to do full logical dump." /bin/false
			exit 1
		}
	}
}

function logging_in_db(){
	mysql_detect

	mysql -h ${MYSQL_HOST} -P ${MYSQL_PORT} -u ${MYSQL_USER} --password="${MYSQL_PASSWD}" 2>/dev/null <<-EOF                                                                                 
		insert into mysql.dump_log(host_name,port,dump_type,dump_sub_type,destination,dump_status,start_time,end_time
				,duration,backupset_size,binlog,binlog_position,error_log)
        select '${MYSQL_HOST}','${MYSQL_PORT}'
				,'$1','$2','$3','$4','$5','$6'
				,unix_timestamp('$6')-unix_timestamp('$5')
				,'$7','$8','$9','${10}';
	EOF
}

function full_dump_xtrabackup(){
	[ -x $MYSQL_HOME/bin/innobackupex ] && {
		DUMP_CMD="$MYSQL_HOME/bin/innobackupex"
	} || {
		[ -x ${MYSQL_TOOL_HOME}/bin/innobackupex ] && {
			DUMP_CMD="${MYSQL_TOOL_HOME}/bin/innobackupex"
		}
	}

	DUMP_CMD="$DUMP_CMD --defaults-file=$mysql_config_file --no-timestamp"
	DUMP_CMD="$DUMP_CMD --host=${MYSQL_HOST} --port=${MYSQL_PORT} --user=${MYSQL_USER} --password=\"${MYSQL_PASSWD}\""
	[ -n "${DUMP_HIGH_PERF}" ] && {
		cpu_num=`cat /proc/cpuinfo | grep processor | wc -l`
		DUMP_CMD="$DUMP_CMD --compress --compress-threads=${cpu_num} --parallel=$cpu_num"
	}

	[ "$DUMP_DESTINATION" = "remote" ] && {
        now=`date +%Y_%m_%d_%H_%M_%S`
        REMOTE_FILE=$REMOTE_DIR/`hostname`_full_${now}.tar.gz
        export PATH=${PATH}:/usr/local/sbin:/usr/local/bin:/root/bin
        which pv > /dev/null 2>&1
        RETVAL=$?
        [ $RETVAL -gt 0 ] && {
            action "[*ERROR*] Please install and configure PV tool." /bin/false
            exit 1
        }
		
		DUMP_CMD="$DUMP_CMD --stream=tar"
		DUMP_CMD="$DUMP_CMD /tmp 2>/dev/null | gzip - | pv -q -L 10M | ssh $DUMP_REMOTELY \"cat - > $REMOTE_FILE\""
		echo "Starting remote physical full dump."
        start_time=`date "+%F %H:%M:%S"`
        eval "$DUMP_CMD"
		[ $? -eq 0 ] && {
			DESTINATION="${DUMP_REMOTELY}:${REMOTE_FILE}"
            size=`ssh $DUMP_REMOTELY "ls -lh $REMOTE_FILE" | cut -d " " -f 5`
			ssh $DUMP_REMOTELY "tar -zxif $REMOTE_FILE ./ xtrabackup_checkpoints"
			to_lsn=`ssh $DUMP_REMOTELY "cat $REMOTE_DIR/xtrabackup_checkpoints" | grep to_lsn | cut -d "=" -f 2 | sed 's/ //g'`
            ssh $DUMP_REMOTELY "[ ${REMOTE_DIR}/xtrabackup_checkpoints ] && rm -rf ${REMOTE_DIR}/xtrabackup_* backup-my.cnf "
			end_time=`date "+%F %H:%M:%S"`
			logging_in_db "Full" "Physical Stream=$to_lsn" "$DESTINATION" "Succeed" "$start_time" "$end_time" "$size" "" "" ""
            action "[*INFO*] Remote full physical dump completed successfully." /bin/true
            exit 0
		} || {
			end_time=`date "+%F %H:%M:%S"`
            logging_in_db "Full" "Physical Stream" "$DUMP_REMOTELY" "Failed" "" "$start_time" "$end_time" "" "" "" ""
            action "[*ERROR*] Failed to do remote physical dump." /bin/false
            exit 1
		}	
	} || {
		now=`date +%Y_%m_%d_%H_%M_%S`
        errorlog=${DUMP_DESTINATION}/`hostname`_full_${now}.error
		DUMP_DESTINATION=${DUMP_DESTINATION}/`hostname`_full_${now}
		DUMP_CMD="$DUMP_CMD ${DUMP_DESTINATION} 2> $errorlog"
		echo "Starting Full physical dump with xtrabackup."
		start_time=`date "+%F %H:%M:%S"`
		eval $DUMP_CMD
		[ $? -eq 0 ] && {
			size=`du -sh ${DUMP_DESTINATION} | cut -d "." -f 1`
			[ -f "${DUMP_DESTINATION}/xtrabackup_binlog_info" ] && binlog_info=`cat ${DUMP_DESTINATION}/xtrabackup_binlog_info`
			binlog=`echo $binlog_info | cut -d " " -f 1 `
			binlog_pos=`echo $binlog_info | cut -d " " -f 2` 
			[ -f "${DUMP_DESTINATION}/xtrabackup_checkpoints" ] && to_lsn=`cat ${DUMP_DESTINATION}/xtrabackup_checkpoints | grep -i to_lsn | cut -d "=" -f 2 | sed 's/ //g'`
			tar -zcvf ${DUMP_DESTINATION}.tar.gz ${DUMP_DESTINATION} >> ${errorlog} 2>&1	
			[ $? -eq 0 ] && rm -rf ${DUMP_DESTINATION} && DUMP_DESTINATION="${DUMP_DESTINATION}.tar.gz" && size=`ls -lh ${DUMP_DESTINATION} | cut -d " " -f 5`
			[ -f $errorlog ] && rm -rf $errorlog
			end_time=`date "+%F %H:%M:%S"`   
			logging_in_db "Full" "$to_lsn" "$DUMP_DESTINATION" "Succeed" "$start_time" "$end_time" "$size" "$binlog" "$binlog_pos" ""
			action "[*INFO*] Full physical dump completed successfully." /bin/true
			exit 0
		} || {
			end_time=`date "+%F %H:%M:%S"`
			[ -d $DUMP_DESTINATION ] && size=`du -sh ${DUMP_DESTINATION} | cut -d "." -f 1`
			logging_in_db "Full" "Physical" "$DUMP_DESTINATION" "Failed" "$start_time" "$end_time" "$size" "" "" "$errorlog"
			action "[*ERROR*] Failed to do full physical dump." /bin/false
			exit 1
		}
	}	
}

function binlog_dump(){
	echo "Starting binlog dump."
	value_debug
}

function incremental_dump(){
	incremental_dump_accumulate
}

function incremental_dump_accumulate(){
	# value_debug
    [ -x $MYSQL_HOME/bin/innobackupex ] && {
        DUMP_CMD="$MYSQL_HOME/bin/innobackupex"
    } || {
        [ -x ${MYSQL_TOOL_HOME}/bin/innobackupex ] && {
            DUMP_CMD="${MYSQL_TOOL_HOME}/bin/innobackupex"
        }
    }

    DUMP_CMD="$DUMP_CMD --defaults-file=$mysql_config_file --no-timestamp"
    DUMP_CMD="$DUMP_CMD --host=${MYSQL_HOST} --port=${MYSQL_PORT} --user=${MYSQL_USER} --password=\"${MYSQL_PASSWD}\""
    [ -n "${DUMP_HIGH_PERF}" ] && {
        cpu_num=`cat /proc/cpuinfo | grep processor | wc -l`
        DUMP_CMD="$DUMP_CMD --compress --compress-threads=${cpu_num} --parallel=$cpu_num"
    }
	
    [ "$DUMP_DESTINATION" = "remote" ] && {
		now=`date +%Y_%m_%d_%H_%M_%S`
        REMOTE_FILE=$REMOTE_DIR/`hostname`_diff_${now}.tar.gz
        export PATH=${PATH}:/usr/local/sbin:/usr/local/bin:/root/bin
        which pv > /dev/null 2>&1
        RETVAL=$?
        [ $RETVAL -gt 0 ] && {
            action "[*ERROR*] Please install and configure PV tool." /bin/false
            exit 1
        }
		
		tmpsql=/tmp/mysql_$RANDOM.sql
		echo "select * from mysql.dump_log where 1=1 and dump_type='Full' and dump_sub_type!='Logical' and lower(dump_sub_type) like '%physical%' and lower(dump_sub_type) like '%stream%' order by start_time desc limit 1\G;" > $tmpsql
		latest_full_dump=`mysql -h ${MYSQL_HOST} -P ${MYSQL_PORT} -u ${MYSQL_USER} --password="${MYSQL_PASSWD}" < ${tmpsql} 2>/dev/null | grep -E "dump_sub_type|destination"`
		from_lsn=`echo $latest_full_dump | cut -d "=" -f 2 | cut -d " " -f 1`		        
		latest_full_dump=`echo $latest_full_dump | cut -d "=" -f 2 | cut -d " " -f 3`

		DUMP_CMD="$DUMP_CMD --stream=tar --incremental --incremental-lsn=$from_lsn"
		DUMP_CMD="$DUMP_CMD /tmp 2>/dev/null | gzip - | pv -q -L 10M | ssh $DUMP_REMOTELY \"cat - > $REMOTE_FILE\""
		echo "Starting remote incremental physical dump."
		start_time=`date "+%F %H:%M:%S"`
        eval "$DUMP_CMD"
		[ $? -eq 0 ] && {
			DESTINATION="${DUMP_REMOTELY}:${REMOTE_FILE}"
			size=`ssh $DUMP_REMOTELY "ls -lh $REMOTE_FILE" | cut -d " " -f 5`
			end_time=`date "+%F %H:%M:%S"`
			logging_in_db "Incremental" "Physical Stream" "$DESTINATION" "Succeed" "$start_time" "$end_time" "$size" "" "" ""
            action "[*INFO*] Remote incremental physical dump completed successfully." /bin/true
            exit 0
		} || {
			end_time=`date "+%F %H:%M:%S"`
            logging_in_db "Incremental" "Physical Stream" "$DUMP_REMOTELY" "Failed" "" "$start_time" "$end_time" "" "" "" ""
            action "[*ERROR*] Failed to do remote incremental physical dump." /bin/false
            exit 1
		}
    } || {
		tmpsql=/tmp/mysql_$RANDOM.sql
		cat <<-EOF > ${tmpsql}
			select *
			from mysql.dump_log
			where 1=1
					and dump_type='Full' 
					and dump_sub_type!='Logical' and lower(dump_sub_type) not like '%physical%'
			order by start_time desc 
			limit 1\G;      
		EOF
		latest_full_dump=`mysql -h ${MYSQL_HOST} -P ${MYSQL_PORT} -u ${MYSQL_USER} --password="${MYSQL_PASSWD}"	 < ${tmpsql} 2>/dev/null | grep -E "dump_sub_type|destination"`
		from_lsn=`echo $latest_full_dump | cut -d ":" -f 2 | cut -d " " -f 2`
		latest_full_dump=`echo $latest_full_dump | cut -d ":" -f 3 | sed 's/ //g'`	
		[ -f ${tmpsql} ] && rm -rf ${tmpsql}   
	
		now=`date +%Y_%m_%d_%H_%M_%S`
        errorlog=${DUMP_DESTINATION}/`hostname`_diff_${now}.error
        DUMP_DESTINATION=${DUMP_DESTINATION}/`hostname`_diff_${now}
        DUMP_CMD="$DUMP_CMD --incremental --incremental-lsn=$from_lsn  ${DUMP_DESTINATION} 2> $errorlog"
		echo "Starting Incremental physical dump with xtrabackup."
        start_time=`date "+%F %H:%M:%S"`
        echo "$DUMP_CMD"
		eval $DUMP_CMD		
		[ $? -eq 0 ] && {
			[ -f "${DUMP_DESTINATION}/xtrabackup_binlog_info" ] && binlog_info=`cat ${DUMP_DESTINATION}/xtrabackup_binlog_info`
            binlog=`echo $binlog_info | cut -d " " -f 1 `
            binlog_pos=`echo $binlog_info | cut -d " " -f 2`
			tar -zcvf ${DUMP_DESTINATION}.tar.gz ${DUMP_DESTINATION} >> ${errorlog} 2>&1
			[ $? -eq 0 ] && rm -rf ${DUMP_DESTINATION} && DUMP_DESTINATION="${DUMP_DESTINATION}.tar.gz" && size=`ls -lh ${DUMP_DESTINATION} | cut -d " " -f 5`
			end_time=`date "+%F %H:%M:%S"`
						
			logging_in_db "Incremental" "$latest_full_dump" "$DUMP_DESTINATION" "Succeed" "$start_time" "$end_time" "$size" "$binlog" "$binlog_pos" ""
			action "[*INFO*] Incremental physical dump completed successfully." /bin/true
            exit 0
		} || {
			end_time=`date "+%F %H:%M:%S"`
            [ -d $DUMP_DESTINATION ] && size=`du -sh ${DUMP_DESTINATION} | cut -d "." -f 1`
            logging_in_db "Incremental" "Physical" "$DUMP_DESTINATION" "Failed" "$start_time" "$end_time" "$size" "" "" "$errorlog"
            action "[*ERROR*] Failed to do incremental physical dump from lsn=${from_lsn}." /bin/false
            exit 1
		}
	}	
}

function control_center(){
	mysql_detect

	[ -z "$DUMP_TYPE" ] && {
		action "[*ERROR*] Backup Type must be specified." /bin/false
		exit 1
	}

	[ -z "$DUMP_DESTINATION" ] && {
		action "[*ERROR*] Backup destination must be specified." /bin/false
		exit 1
	} || {
		DUMP_DESTINATION=`echo $DUMP_DESTINATION | tr [A-Z] [a-z]`
		[ $DUMP_DESTINATION = "remote" ] && {
			if [ -z "$REMOTE_HOST" -o -z "$REMOTE_DIR" ] 
			  then
				action "[*ERROR*] Remote parameters must be specified." /bin/false
				exit 1	
			else
				if [ -z "$REMOTE_USER" ]
                  then
                    action "[*ERROR*] Remote parameters must be specified." /bin/false
                    exit 1
                fi
				DUMP_REMOTELY="${REMOTE_USER}@${REMOTE_HOST}"
			fi
		} || {
			[ ! -d ${DUMP_DESTINATION} ] && {
				action "[*ERROR*] Backup destination doesn't exists!" /bin/false
				exit 1
			}
		}
	}
	
	DUMP_TYPE=`echo $DUMP_TYPE | tr [a-z] [A-Z]`
	if [ "$DUMP_TYPE" = "FULL" ] 
	  then
		[ ! -z "$LOGICAL_DUMP" -a "$LOGICAL_DUMP" = "Y" ] && {
			full_dump_mysqldump
		} || {
			full_dump_xtrabackup
		}
	elif [ "$DUMP_TYPE" = "INCREMENTAL" ]
	  then
		[ ! -z "$ACCUMULATE_DUMP" -a "$ACCUMULATE_DUMP" = "Y" ] && {
			incremental_dump_accumulate
		} || {
			incremental_dump
		}	
	elif [ "$DUMP_TYPE" = "BINLOG" ]
	  then
			binlog_dump
	fi
}

function parse_options(){
    [ `echo "$*" | grep "\--" | wc -l` -eq 0 ] && {
		[ $# -eq 0 ] && {
			action "[*ERROR*] Parameters required." /bin/false
			exit 1
		} || {
			action "[*ERROR*] Invalid options." /bin/false
			exit 1
		}
    }

	options=`getopt -o h --long help,high-perf,type:,logical,accumulate,destination:,remote-user:,remote-host:,remote-dir:,host:,user:,password:,port:  -- "$@" 2>/dev/null`
	# surpress error messages generated by getopt.
	#	1. unrecognized option --helo
	#	2. option `--type' requires an argument	
	[ $? -gt 0 ] && {
		action "[*ERROR*] Invalid options or arguements are required." /bin/false
		exit 1
	}
	eval set -- "$options"
	
    while true
    do
        case $1 in
			--help)
					usage
					exit 0
					;;
			--high-perf)
                    DUMP_HIGH_PERF="Y"
                    shift
                    ;;
			--type)
                    DUMP_TYPE=$2
                    shift 2
                    ;;
			--logical)
                    LOGICAL_DUMP="Y"
                    shift 
                    ;;
			--accumulate)
                    ACCUMULATE_DUMP="Y"
                    shift 
                    ;;
			--destination)
                    DUMP_DESTINATION=$2
                    shift 2
                    ;;
			--remote-user)
					REMOTE_USER=$2	
                    shift 2
                    ;;
			--remote-host)
					REMOTE_HOST=$2
                    shift 2
                    ;;
			--remote-dir)
					REMOTE_DIR=$2
                    shift 2
                    ;;
            --host)
                    MYSQL_HOST=$2
                    shift 2
                    ;;
            --user)
                    MYSQL_USER=$2
                    shift 2
                    ;;
            --password)
                    MYSQL_PASSWD=$2
                    shift 2
                    ;;
            --port)
                    MYSQL_PORT=$2
                    shift 2
                    ;;
            --)
                    shift
                    break
					;;
            *)
                    action "[*ERROR*] Invalid options $1."  /bin/false
                    exit 1
					;;
        esac
    done
}
# ****************************************************************************
# Main Control Flow
#
loading_functions
loading_default_settings
parse_options $*
loading_mysql_config_file
control_center
