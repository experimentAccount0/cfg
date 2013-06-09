import re
from util import ValidationError

class Defaults:
    def __init__(self, data, errors):
        def check(data, item, descr):
            if type(data) is not dict or not item in data:
                errors.append(ValidationError('no %s' % descr))
            else:
                return data[item]

        self.network_prefix = check(data, 'network_prefix', 'default network prefix')

        self.domains = {}
        self.def_domain = None

        domains = check(data, 'domains', 'domain substitution rules')

        if type(domains) == dict:
            for key, value in domains.iteritems():
                if key == 'default':
                    self.def_domain = value
                else:
                    for oldkey in self.domains.iterkeys():
                        if key.endswith(oldkey) or oldkey.endswith(key):
                            errors.append(ValidationError('two keys in domain defaults config have ' +
                                ('common suffix: %s and %s' % (key, oldkey))))
                    self.domains[key] = value

        if not self.def_domain:
            errors.append(ValidationError('no default domain configured'))

    def expand_host(self, host):
        if '.' in host:
            for patt, subst in self.domains.iteritems():
                if host.endswith(patt):
                    return host[0:host.rindex(patt)] + subst
            return host

        return '%s.%s' % (host, self.def_domain)

    def expand_ip(self, ip):
        return ('%s.%s' % (self.network_prefix, ip)
                if not re.match('^\d+\.\d+\.\d+\.\d+$', str(ip))
                else ip)
