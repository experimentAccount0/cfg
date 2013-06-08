#!/opt/local/bin/python2.7

import json, sys, yaml, re, copy

from parse          import defaults
from parse.host     import Host, check_hosts
from parse.group    import Group, expand_groups
from parse.network  import Network, choose

from gen import dhcp, dns, iptables

if __name__ == '__main__':
    cfg = yaml.load(sys.stdin)
    errors = []
    errors.extend(defaults.init(cfg['defaults']))

    hosts    = map(Host,    cfg['hosts'])
    networks = map(Network, cfg['networks'])
    groups   = map(Group,   cfg['groups'])

    users    = cfg['users'] if 'users' in cfg else []

    errors.extend(check_hosts(hosts))
    errors.extend(expand_groups(groups, hosts))
    map(Host.clean, hosts)

    if len(errors):
        for error in errors: print >> sys.stderr, 'Error: %s' % error
        sys.exit(1)
    else:
        #with open('cfg/dhcp.template', 'r') as dhcpt:
        #    template = dhcpt.read()
        #print dhcp.gen(hosts, template, networks)

        #with open('cfg/urgu.org.template', 'r') as dnst:
        #    template = dnst.read()
        #print dns.gen_fwd(hosts, template, 'urgu.org')

        #with open('cfg/reverse.template', 'r') as rdnst:
        #    template = rdnst.read()
        #print dns.gen_reverse(hosts, template, 12345, choose(networks, '172.16.12'))

        with open('cfg/fb.template', 'r') as rdnst:
            template = rdnst.read()
        print dns.gen_fb(hosts, template, 12345, choose(networks, '172.16.12'))

        #print ''.join(iptables.gen_ports(hosts, '194.226.244.126', 'server'))

        #for host in hosts: print host
        #for network in networks: print network; print network.get_dhcp()
