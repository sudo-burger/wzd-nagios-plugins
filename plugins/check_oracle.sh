#! /bin/bash
# Nagios plugin for Oracle
# Maintainer: Federico Pietrolucci (Wozhidao AB) <federico@wozhidao.com>
# 
# SEE ALSO
# Nagios Plugins Development Guidelines (NPDG):
# https://nagios-plugins.org/doc/guidelines.html
# Nagios performance data format:
# https://assets.nagios.com/downloads/nagioscore/docs/nagioscore/4/en/perfdata.html

# Exit immediately if a command fails.
set -e
# Treat the expansion of undefined variables as an error.
set -u
# Turn off globbing, which would cause SQL code to be interpreted as bash code.
set -f

# The NPDG requires all output to be to stdout.
exec 2>&1

PROGNAME=$(basename "$0")

# DEBUG = 1 enables the debug() function.
DEBUG=0

# Output functions
function xout() {
  echo "$*"
}
function debug() {
  [[ "$DEBUG" -eq 1 ]] && echo "DEBUG: $*"
}
function warn() {
  echo "WARNING: $*"
}
function err() {
  xout "ERROR: $*"
  exit 3
}
usage() {
  local exit_code="${1:-0}"
  xout "$PROGNAME
    -H|--host <host>
    -P|--port <port>
    -S|--SID <SID>
    -u|--user <db user>
    -p|--password <db password>
    -w|--warning <warning threshold>
    -c|--critical <critical threshold>
    -M|--mode [dgSst]
      Modes:
      d: number of deadlocks
      g: percent used ASM diskgroup
      S: percent used sessions of max configured
      s: number of active user sessions
      t: percent used of tablespace (requires -t)
    -g|--asm-diskgroup <ASM diskgroup name>
    -t|--tablespace <tablespace name>
    -h|--help"
  exit "$exit_code"
} 

# SQL helper. Basically a wrapper for the Oracle client.
#
function run_sql() {
  local host="$1"
  local port="$2"
  local SID="$3"
  local dbuser="$4"
  local dbpass="$5"
  local sql="$6"

  sqlplus -s "$dbuser/$dbpass@$host:$port/$SID" << EOF
set heading off
set linesize 10000
set long 10000000
set serveroutput on
set termout on
whenever oserror exit 68;
whenever sqlerror exit sql.sqlcode;
$sql
EOF
}

# Trim leading and trailing spaces.
function trim() {
  echo "$*"|sed -e 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

# Abort if the input is not numeric.
function assert_is_number() {
  if [ -n "$1" ] && [ "$1" -eq "$1" ] 2>/dev/null; then
    return
  else
    err "[${FUNCNAME[0]}] Not a number: $1; callstack: ${FUNCNAME[*]}"
  fi
}

# Parse the command line arguments
# ================================
#
# Short and long command line options, in getopt format.
OPTIONS=H:P:S:u:p:w:c:M:t:g:h
LONGOPTS=host:,port:,SID:,user:,password:,warning:,critical:,mode:,tablespace:,asm-diskgroup:,help

PARSED_ARGUMENTS=$(getopt -n "$PROGNAME" -o "$OPTIONS" --long "$LONGOPTS" -- "$@") \
    || usage 3

host="HOST"
port="1521"
SID="SID"
dbuser="DBUSER"
dbpass="DBPASS"
mode=""
warning=0
critical=0
out=""
status=""
tablespace="UNKNOWN"

eval set -- "$PARSED_ARGUMENTS"
while : ; do
  case "$1" in
    -H|--host) host=$2; shift 2 ;;
    -P|--port) port=$2; shift 2 ;;
    -S|--SID)  SID=$2; shift 2 ;;
    -u|--user) dbuser=$2; shift 2 ;;
    -p|--password) dbpass=$2; shift 2 ;;
    -w|--warning)  warning=$2; shift 2 ;; 
    -c|--critical)  critical=$2; shift 2 ;; 
    -M|--mode)  mode=$2; shift 2 ;;
    -t|--tablespace)  tablespace=$2; shift 2 ;;
    -g|--asm-diskgroup) diskgroup=$2; shift 2 ;;
    -h|--help) usage 0;;
    --) shift; break;;
     *) usage 1;;
  esac
done

# Command line args sanity checks.
#
if ((warning > critical)); then
  err "The warning value can not be higher than the warning value."
fi

# Choose SQL query based on --mode argument.
#
case $mode in
  d)
    # Number of deadlocks.
    sql="
      select
        count(*)
      from
        gv\$lock l1
      join
        gv\$session s1
      on
        l1.sid = s1.sid
      and
        L1.inst_id = s1.inst_id
      join
        gv\$lock l2
      on
        l1.id1 = l2.id1
      and
        l1.inst_id = l2.inst_id
      join
        gv\$session s2
      on
        l2.sid = s2.sid
      and
        l1.inst_id = s2.inst_id
      where
        l1.block = 1 and l2.request > 0;"
    ;;
  g)
    sql="
      select
        round((total_mb-free_mb)/total_mb*100) as used_pct
      from
        v\$asm_diskgroup
      where
        name = \'$diskgroup\';"
    ;;
  S)
    # Sessions: used percent of max
    sql="
      select
        round(current_utilization / limit_value * 100)
      from
        v\$resource_limit
      where
        resource_name = 'sessions';"
    ;;
  s)
    # Sessions: number of active user sessions.
    sql="select count(*) from v\$session where type = 'USER';"
    ;;
  t)
    # Tablespace: used percent
    sql="
      with
      tot as (
        select
          tablespace_name,
          sum(bytes) as allocated_bytes,
          sum(
            case autoextensible
              when 'YES' then maxbytes
              else bytes
            end) as max_bytes
        from
          dba_data_files
        group by
          tablespace_name
      ),
      free as (
        select
          tablespace_name,
          sum(bytes) as bytes
        from
          dba_free_space
        group by
          tablespace_name
      ),
      D0 as (
        select
          tot.tablespace_name,
          round((tot.allocated_bytes - coalesce(free.bytes, 0))/tot.max_bytes*100) as pct_used
        from
          tot
        left join
          free
        on
          tot.tablespace_name = free.tablespace_name
        union all
        select
          tablespace_name,
          round(100*((tablespace_size-free_space)/nullif(tablespace_size, 0))) as pct_used
        from
          dba_temp_free_space
      )
      select
        pct_used
      from
        D0
      where
        tablespace_name = \'$tablespace\';"
    ;;
  *)
    xout "Unknown mode: $mode"
    usage 1
    ;;
esac

# Execute SQL and build conformant output for Nagios, including the
# "performance data" section. See:
# https://assets.nagios.com/downloads/nagioscore/docs/nagioscore/4/en/perfdata.html
#
out=$(run_sql "$host" "$port" "$SID" "$dbuser" "$dbpass" "$sql") \
    || err "Unable to run SQL: $out"

# Validate the query's output.
#
out=$(trim "$out")
assert_is_number "$out"

# Exit status as required by NPDG.
#
if ((out >= critical)); then
  status="Critical"
  ret=2
elif ((out >= warning)); then
  status="Warning"
  ret=1
else
  status="OK"
  ret=0
fi

echo "$status: $out| actual=$out"
exit $ret
