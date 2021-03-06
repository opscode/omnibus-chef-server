#
# Copyright:: Copyright (c) 2012 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'mixlib/shellout'

class PgHelper
  attr_reader :node

  def initialize(node)
    @node = node
  end

  def run_command(cmd, options)
    cmd = Mixlib::ShellOut.new(cmd, options)
    cmd.run_command
    cmd
  end


  def is_running?
    OmnibusHelper.service_up?("postgresql")
  end

  def database_exists?(db_name)
    psql_cmd(["-d 'template1'",
              "-c 'select datname from pg_database' -x",
              "| grep #{db_name}"])
  end

  def managed_by_sqitch?
    # This method has an issue: if sqitch isn't on the box, a 1 will
    # be returned. However, if sqitch is on the box and verify fails,
    # a one will also be returned.
    # In the event verify fails and sqitch is on the box, a later call
    # to deploy will fail. A failed deploy could therefore be a
    # symptom that verify failed.
    cmd = run_command "sqitch --db-user #{db_user} verify",
      :cwd     => '/opt/chef-server/embedded/service/chef-server-schema',
      :user    => db_user,
      :returns => [0, 1]
    cmd.exitstatus == 0
  end

  def needs_schema_update?
    cmd = run_command "sqitch --db-user #{db_user} status",
      :cwd     => '/opt/chef-server/embedded/service/chef-server-schema',
      :returns => [0, 1, 2]
    cmd.stdout !~ /^Nothing to deploy \(up-to-date\)$/
  end

  def db_user
    node['chef_server']['postgresql']['username']
  end

  def sql_user_exists?
    user_exists?(node['chef_server']['postgresql']['sql_user'])
  end

  def sql_ro_user_exists?
    user_exists?(node['chef_server']['postgresql']['sql_ro_user'])
  end

  def user_exists?(db_user)
    psql_cmd(["-d 'template1'",
              "-c 'select usename from pg_user' -x",
              "|grep #{db_user}"])
  end

  def psql_cmd(cmd_list)
    cmd = ["/opt/chef-server/embedded/bin/chpst",
           "-u #{pg_user}",
           "/opt/chef-server/embedded/bin/psql",
           "--port #{pg_port}",
           cmd_list.join(" ")].join(" ")
    do_shell_out(cmd, 0)
  end

  def pg_user
    node['chef_server']['postgresql']['username']
  end

  def pg_port
    node['chef_server']['postgresql']['port']
  end

  def do_shell_out(cmd, expect_status)
    o = Mixlib::ShellOut.new(cmd)
    o.run_command
    o.exitstatus == expect_status
  end

end

class OmnibusHelper
  attr_reader :node

  def initialize(node)
    @node = node
  end

  # Normalizes hosts. If the host part is an ipv6 literal, then it
  # needs to be quoted with []
  def self.normalize_host(host_part)
    # Make this simple: if ':' is detected at all, it is assumed
    # to be a valid ipv6 address. We don't do data validation at this
    # point, and ':' is only valid in an URL if it is quoted by brackets.
    if host_part =~ /:/
      "[#{host_part}]"
    else
      host_part
    end
  end

  def normalize_host(host_part)
    self.class.normalize_host(host_part)
  end

  def vip_for_uri(service)
    normalize_host(node['chef_server'][service]['vip'])
  end

  def self.should_notify?(service_name)
    File.symlink?("/opt/chef-server/service/#{service_name}") && service_up?(service_name)
  end

  def self.service_up?(service_name)
    o = Mixlib::ShellOut.new("/opt/chef-server/bin/chef-server-ctl status #{service_name}")
    o.run_command
    o.exitstatus == 0
  end

  # generate a certificate signed by the opscode ca key
  #
  # === Returns
  # [cert, key]
  #
  def self.gen_certificate
    key = OpenSSL::PKey::RSA.generate(2048)
    public_key = key.public_key
    cert_uuid = UUIDTools::UUID.random_create
    common_name = "URI:http://opscode.com/GUIDS/#{cert_uuid}"
    info = [["C", "US"], ["ST", "Washington"], ["L", "Seattle"], ["O", "Opscode, Inc."], ["OU", "Certificate Service"], ["CN", common_name]]
    cert = OpenSSL::X509::Certificate.new
    cert.subject = OpenSSL::X509::Name.new(info)
    cert.issuer = ca_certificate.subject
    cert.not_before = Time.now
    cert.not_after = Time.now + 10 * 365 * 24 * 60 * 60 # 10 years
    cert.public_key = public_key
    cert.serial = 1
    cert.version = 3

    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = ca_certificate
    cert.extensions = [
                       ef.create_extension("basicConstraints","CA:FALSE",true),
                       ef.create_extension("subjectKeyIdentifier", "hash")
                      ]
    cert.sign(ca_keypair, OpenSSL::Digest::SHA1.new)

    return cert, key
  end

  ######################################################################
  #
  # the following is the Opscode CA key and certificate, copied from
  # the cert project(s)
  #
  ######################################################################

  def self.ca_certificate
    @_ca_cert ||=
      begin
        cert_string = <<-EOCERT
-----BEGIN CERTIFICATE-----
MIIDyDCCAzGgAwIBAwIBATANBgkqhkiG9w0BAQUFADCBnjELMAkGA1UEBhMCVVMx
EzARBgNVBAgMCldhc2hpbmd0b24xEDAOBgNVBAcMB1NlYXR0bGUxFjAUBgNVBAoM
DU9wc2NvZGUsIEluYy4xHDAaBgNVBAsME0NlcnRpZmljYXRlIFNlcnZpY2UxMjAw
BgNVBAMMKW9wc2NvZGUuY29tL2VtYWlsQWRkcmVzcz1hdXRoQG9wc2NvZGUuY29t
MB4XDTA5MDUwNjIzMDEzNVoXDTE5MDUwNDIzMDEzNVowgZ4xCzAJBgNVBAYTAlVT
MRMwEQYDVQQIDApXYXNoaW5ndG9uMRAwDgYDVQQHDAdTZWF0dGxlMRYwFAYDVQQK
DA1PcHNjb2RlLCBJbmMuMRwwGgYDVQQLDBNDZXJ0aWZpY2F0ZSBTZXJ2aWNlMTIw
MAYDVQQDDClvcHNjb2RlLmNvbS9lbWFpbEFkZHJlc3M9YXV0aEBvcHNjb2RlLmNv
bTCBnzANBgkqhkiG9w0BAQEFAAOBjQAwgYkCgYEAlKTCZPmifZe9ruxlQpWRj+yx
Mxt6+omH44jSfj4Obrnmm5eqVhRwjSfHOq383IeilFrNqC5VkiZrlLh8uhuTeaCy
PE1eED7DZOmwuswTui49DqXiVE39jB6TnzZ3mr6HOPHXtPhSzdtILo18RMmgyfm/
csrwct1B3GuQ9LSVMXkCAwEAAaOCARIwggEOMA8GA1UdEwEB/wQFMAMBAf8wHQYD
VR0OBBYEFJ228MdlU86GfVLsQx8rleAeM+eLMA4GA1UdDwEB/wQEAwIBBjCBywYD
VR0jBIHDMIHAgBSdtvDHZVPOhn1S7EMfK5XgHjPni6GBpKSBoTCBnjELMAkGA1UE
BhMCVVMxEzARBgNVBAgMCldhc2hpbmd0b24xEDAOBgNVBAcMB1NlYXR0bGUxFjAU
BgNVBAoMDU9wc2NvZGUsIEluYy4xHDAaBgNVBAsME0NlcnRpZmljYXRlIFNlcnZp
Y2UxMjAwBgNVBAMMKW9wc2NvZGUuY29tL2VtYWlsQWRkcmVzcz1hdXRoQG9wc2Nv
ZGUuY29tggEBMA0GCSqGSIb3DQEBBQUAA4GBAHJxAnwTt/liAMfZf5Khg7Mck4f+
IkO3rjoI23XNbVHlctTOieSwzRZtBRdNOTzQvzzhh1KKpl3Rt04rrRPQvDeO/Usm
pVr6g+lk2hhDgKKeR4J7qXZmlemZTrFZoobdoijDaOT5NuqkGt5ANdTqzRwbC9zQ
t6vXSWGCFoo4AEic
-----END CERTIFICATE-----
EOCERT
        OpenSSL::X509::Certificate.new(cert_string)
      end
  end

  def self.ca_keypair
    @_ca_key ||=
      begin
        keypair_string = <<-EOKEY
-----BEGIN RSA PRIVATE KEY-----
MIICWwIBAAKBgQCUpMJk+aJ9l72u7GVClZGP7LEzG3r6iYfjiNJ+Pg5uueabl6pW
FHCNJ8c6rfzch6KUWs2oLlWSJmuUuHy6G5N5oLI8TV4QPsNk6bC6zBO6Lj0OpeJU
Tf2MHpOfNneavoc48de0+FLN20gujXxEyaDJ+b9yyvBy3UHca5D0tJUxeQIDAQAB
AoGAYAPRIeJyiIfk2cIPYqQ0g3BTwfyFQqJl6Z7uwOca8YEZqfWc7L+FOFiyg3/x
rw3aAdRptbJASgiRQ16sCpdXeaRFY5gcO2MnqmCyoyp2//zhdFReSC+Akim1UPtG
5SqqdV9I0TBl+1JlMiivn677mXGij+qyQjSWxW2pGVsbTSUCQQDDLb/DgoD0+N6O
FIoJ/Mh5cgIxQhqXu/dylEv/I3goSJdXPAqhsnsa6zYQGdftnvMK1ZXS/hYL4i06
w9lKDV8PAkEAwvaz1oUtXLNfYYAF42c1BoBhqCzjXSzMWPu5BlWQzSsdzgVgDuX3
LlkiIdRtMcMaNskaBTtIClCxaEm3rUnm9wJAEOp2JEu7QYAQSeAd1p/CAESRTBOe
mmgAGj4gGAzK7TLdawIZKcp+QOcB2INk44NTLS01vwOmhYEkymMPAgwGoQJAKimq
GMFyXvLXtME4BMbEG+TVucYDYZoXk0LU776/cu9ZIb3d2Tr4asiR7hj/iFx2JdT1
0J3SZZCv3SrcExjBXwJABS3/iQroe24tvrmyy4tc5YG5ygIRaBUCs6dn0fbisX/9
K1oq5Lnwimy4l2NI0o/lxIqnwFilACjs3tuXH1OhMA==
-----END RSA PRIVATE KEY-----
EOKEY
        OpenSSL::PKey::RSA.new(keypair_string)
      end
  end

  def self.erl_atom_or_string(term)
    case term
    when Symbol
      term
    when String
      "\"#{term}\""
    else
      "undefined"
    end
  end

  def erl_atom_or_string(term)
    self.class.erl_atom_or_string(term)
  end
end

