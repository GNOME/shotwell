import os.path
import apport.hookutils

def add_info(report):
    log_file = os.path.expanduser('~/.cache/shotwell/shotwell.log')
    apport.hookutils.attach_file_if_exists(report, log_file, 'shotwell.log')

