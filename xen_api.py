#!/usr/bin/env python
# -*- coding: utf-8 -*-

import XenAPI
import sys

hostname, username, password = "localhost", "root", "password"

try:
    session = XenAPI.Session('https://'+hostname)
    session.login_with_password(username, password)
except XenAPI.Failure, error:
    if error.details[0]=='HOST_IS_SLAVE':
        print "%s is slave! Master is %s" % (hostname, e.details[1])
        session = XenAPI.Session('https://'+e.details[1])
        session.login_with_password(username, password)
    else:
        raise

print "Session is: %s" % session.handle
pools = session.xenapi.pool.get_all()
print "Pool Name is: %s" % session.xenapi.pool.get_name_label(pools[0])
master_ref = session.xenapi.pool.get_master(pools[0])
print "Master is: %s" % session.xenapi.host.get_name_label(master_ref)

host_refs = session.xenapi.host.get_all()
for host_ref in host_refs:
    print session.xenapi.host.get_name_label(host_ref)
    vmrs = session.xenapi.host.get_resident_VMs(host_ref)
    for vmr in vmrs:
        if not session.xenapi.VM.get_record(vmr)["is_a_template"]:
            if not session.xenapi.VM.get_is_control_domain(vmr):
                print "\t'%s' -> %s -> %s" % ( session.xenapi.VM.get_name_label(vmr)
                                             , session.xenapi.VM.get_uuid(vmr)
                                             , session.xenapi.VM.get_power_state(vmr)
                                             )
