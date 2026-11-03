#!/usr/bin/env python3
"""Regression: run NVIDIA's actual target sanitizer against our disk guard."""
import pathlib,re,subprocess,sys
source=pathlib.Path(sys.argv[1]).read_text()
match=re.search(r'^sanitize_force_bootdisk_input\(\)\n\{.*?^\}',source,re.M|re.S)
assert match
custom=(pathlib.Path(__file__).with_name('customize-iso.py')).read_text()
guard=re.search(r'    case "\$G_FORCE_BOOTDISK" in.*?    esac',custom,re.S).group()
preamble='''set -e
lsblk() { printf '%s\\n' nvme0n1 sda nvme1n1; }
echo_log() { :; }
G_BOOT_DISK_DETECT_FAIL=false
'''
for value,allowed in [('nvme0n1',True),('/dev/nvme0n1',True),('sda',False),('nvme1n1',False),('nvme0n1,sda',False)]:
 result=subprocess.run(['bash','-c',preamble+match.group()+'\nG_FORCE_BOOTDISK="$1"\nsanitize_force_bootdisk_input\n'+guard,'test',value],capture_output=True,text=True)
 assert (result.returncode==0)==allowed,(value,result.returncode,result.stderr)
 print(f'{value}: {"accepted" if allowed else "rejected"}')
# efivarfs does not support seeking; exercise the actual board check through
# a non-seekable descriptor with the 4-byte EFI attributes prefix.
import os
board_guard=re.search(r'    if ! test -r "\$spec".*?    fi',custom,re.S).group()
# The Python customization source escapes the shell NUL deletion once.
board_guard=board_guard.replace("'\\\\000'", "'\\000'")
for board,allowed in [('3767-000-0000-A.0-1-2-p3509-a02-p3767-0000-',True),('3767-000-0000-A.0-1-2-other-carrier-',False)]:
 read_fd,write_fd=os.pipe()
 os.write(write_fd,b'\x07\x00\x00\x00'+board.encode()+b'\x00');os.close(write_fd)
 try:
  result=subprocess.run(['bash','-c','spec="$1"\n'+board_guard,'test',f'/proc/self/fd/{read_fd}'],pass_fds=(read_fd,),capture_output=True,text=True)
  assert (result.returncode==0)==allowed,(board,result.stderr)
 finally: os.close(read_fd)
 print(f'Non-seekable firmware record: {"accepted" if allowed else "rejected"}')
