
## check_oracle.sh
    Usage:
      -H|--host <host>
      -P|--port <port>
      -S|--SID <SID>
      -u|--user <db user>
      -p|--password <db password>
      -w|--warning <warning threshold>
      -c|--critical <critical threshold>
      -M|--mode [Sst]
        Modes:
        d: number of deadlocks
        g: percent used ASM diskgroup
        S: percent used sessions of max configured
        s: number of active user sessions
        t: percent used of tablespace (requires -t)
      -g|--asm-diskgroup <ASM diskgroup name>
      -t|--tablespace <tablespace name>
      -h|--help
