
# iotop

```
> sudo dnf install iotop
> sudo iotop -bktoqqq
b'10:34:52     102 ?sys root        0.00 K/s   11.11 K/s ?unavailable?  [jbd2/mmcblk0p3-8]'
b'10:34:56  211647 ?sys 444        89.16 K/s   29.72 K/s ?unavailable?  Prowlarr -nobrowser -data=/config [.NET ThreadPool]'
b'10:34:56    4004 ?sys root        0.00 K/s    7.43 K/s ?unavailable?  containerd'
b'10:34:56  212025 ?sys 444         0.00 K/s    3.71 K/s ?unavailable?  Prowlarr -nobrowser -data=/config [.NET ThreadPool]'
b'10:34:56    7211 ?sys root        0.00 K/s    0.00 K/s ?unavailable?  containerd-shim-runc-v2 -namespace k8s.io -id 552ace7817fe9c4a8bbec72f39028d7ca20218eac93309efc3e3f68785b242d9 -address /run/k3s/containerd/containerd.sock'
b'10:34:58     102 ?sys root        0.00 K/s    3.70 K/s ?unavailable?  [jbd2/mmcblk0p3-8]'
b'10:35:03    7242 ?sys root        0.00 K/s    0.00 K/s ?unavailable?  containerd-shim-runc-v2 -namespace k8s.io -id 552ace7817fe9c4a8bbec72f39028d7ca20218eac93309efc3e3f68785b242d9 -address /run/k3s/containerd/containerd.sock'
b'10:35:05  212025 ?sys 444         0.00 K/s    3.71 K/s ?unavailable?  Prowlarr -nobrowser -data=/config [.NET ThreadPool]'
b'10:35:05    7242 ?sys root        0.00 K/s    0.00 K/s ?unavailable?  containerd-shim-runc-v2 -namespace k8s.io -id 552ace7817fe9c4a8bbec72f39028d7ca20218eac93309efc3e3f68785b242d9 -address /run/k3s/containerd/containerd.sock'
b'10:35:07  211647 ?sys 444        88.54 K/s   29.51 K/s ?unavailable?  Prowlarr -nobrowser -data=/config [.NET ThreadPool]'
b'10:35:07     399 ?sys root        0.00 K/s    3.69 K/s ?unavailable?  rsyslogd -n [rs:main Q:Reg]'
```

ext4 journal tracing: https://bugzilla.kernel.org/show_bug.cgi?id=39072#c4
```
[root@k3-n1 ~]# sudo su -
[root@k3-n1 ~]# echo 1 > /sys/kernel/debug/tracing/events/jbd2/jbd2_run_stats/enable
[root@k3-n1 ~]# echo 1 > /sys/kernel/debug/tracing/events/ext4/ext4_journal_start/enable
[root@k3-n1 ~]# cat /sys/kernel/debug/tracing/trace_pipe
 containerd-shim-1923    [000] .....  4202.155527: ext4_journal_start: dev 179,3 blocks 24, rsv_blocks 0, revoke_creds 8, caller __ext4_unlink+0xe8/0x330
 containerd-shim-1923    [000] .....  4202.155627: ext4_journal_start: dev 179,3 blocks 29, rsv_blocks 0, revoke_creds 8, caller ext4_evict_inode+0x274/0x5b0
 jbd2/mmcblk0p3--101     [001] ...1.  4207.846433: jbd2_run_stats: dev 179,3 tid 54627 wait 0 request_delay 0 running 5788 locked 0 flushing 0 logging 0 handle_count 4 blocks 6 blocks_logged 8
 containerd-shim-1925    [001] .....  4212.058241: ext4_journal_start: dev 179,3 blocks 53, rsv_blocks 0, revoke_creds 8, caller __ext4_new_inode+0xab8/0x1400
...

[root@k3-n1 ~]# echo 0 > /sys/kernel/debug/tracing/events/jbd2/jbd2_run_stats/enable
[root@k3-n1 ~]# echo 0 > /sys/kernel/debug/tracing/events/ext4/ext4_journal_start/enable
```
