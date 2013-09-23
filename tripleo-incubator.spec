Name:           tripleo-incubator
Version:        0.0.1
Release:        1%{?dist}
Summary:        An incubator where we incubate new ideas and new tools for TripleO for OpenStack

Group:          Applications/System
License:        Apache License (2.0)
URL:            https://wiki.openstack.org/wiki/TripleO
Source0:        https://github.com/openstack/%{name}/%{name}-%{version}.tar.gz


%description
TripleO is our pithy term for OpenStack deployed on and 
with OpenStack.  This is an incubator where we incubate new ideas and 
new tools which get us closer to our goal.  We we move tools to 
permanent homes in https://github.com/stackforge once they have proved 
that they do need to exist. Other times we will propose the tool for 
inclusion in an existing project (such as nova or glance).

%prep
%setup -q -n %{name}

%install
# Setup directories
install -d -m 755 %{buildroot}%{_sharedstatedir}/%{name}
install -d -m 755 %{buildroot}%{_sharedstatedir}/%{name}/scripts
install -d -m 755 %{buildroot}%{_sharedstatedir}/%{name}/templates
install -d -m 755 %{buildroot}%{_sharedstatedir}/%{name}/libvirt-templates
install -p -m 755 scripts/* %{buildroot}%{_sharedstatedir}/%{name}/scripts
install -p -m 755 templates/* %{buildroot}%{_sharedstatedir}/%{name}/templates
install -p -m 755 libvirt-templates/* %{buildroot}%{_sharedstatedir}/%{name}/libvirt-templates
install -p -m 755 cloudprompt %{buildroot}%{_sharedstatedir}/%{name}/
install -p -m 755 overcloudrc %{buildroot}%{_sharedstatedir}/%{name}/
install -p -m 755 overcloudrc-user %{buildroot}%{_sharedstatedir}/%{name}/
install -p -m 755 seedrc %{buildroot}%{_sharedstatedir}/%{name}/
install -p -m 755 undercloudrc %{buildroot}%{_sharedstatedir}/%{name}/

%files
%doc *.md
%doc *.txt
%defattr(-, root, root, -)
%dir %{_sharedstatedir}/%{name}
%dir %{_sharedstatedir}/%{name}/scripts
%dir %{_sharedstatedir}/%{name}/templates
%dir %{_sharedstatedir}/%{name}/libvirt-templates
%{_sharedstatedir}/%{name}/*
%{_sharedstatedir}/%{name}/scripts/*
%{_sharedstatedir}/%{name}/libvirt-templates/*
%{_sharedstatedir}/%{name}/templates/*


%changelog
* Mon Sep 23 2013 Ryan Brady <rbrady@redhat.com> 0.0.1
- Initial RPM build
