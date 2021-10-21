## check_oracle.sh
Nagios plugin for monitoring Oracle databases.

    Usage:
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
        -h|--help

Note that 'sqlplus' must be in PATH for this plugin to function.
