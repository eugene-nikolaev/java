#
# Author:: Kyle McGovern (<spion06@gmail.com>)
# Cookbook Name:: java
# Recipe:: oracle_jce
#
# Copyright 2014, Kyle McGovern
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

include_recipe 'java::set_attributes_from_version'

jdk_version = node['java']['jdk_version'].to_s
jce_url = node['java']['oracle']['jce'][jdk_version]['url']
jce_checksum = node['java']['oracle']['jce'][jdk_version]['checksum']
jce_cookie = node['java']['oracle']['accept_oracle_download_terms'] ? 'oraclelicense=accept-securebackup-cookie;gpw_e24=http://edelivery.oracle.com' : ''

checksum_bin = if jce_checksum =~ /^[0-9a-f]{32}$/
                 'md5sum'
               else
                 'sha256sum'
               end

directory ::File.join(node['java']['oracle']['jce']['home'], jdk_version) do
  mode '0755'
  recursive true
  action :create
end

if node['os'] == 'windows'
  include_recipe 'windows'

  url = node['java']['oracle']['jce'][jdk_version]['url']
  zip_checksum = node['java']['oracle']['jce'][jdk_version]['checksum']
  staging_path = ::File.join(node['java']['oracle']['jce']['home'], jdk_version)
  staging_local_policy = ::File.join(staging_path, "UnlimitedJCEPolicyJDK#{jdk_version}", 'local_policy.jar')
  staging_export_policy = ::File.join(staging_path, "UnlimitedJCEPolicyJDK#{jdk_version}", 'US_export_policy.jar')
  jre_final_path = ::File.join(node['java']['java_home'], 'jre', 'lib', 'security')
  final_local_policy = ::File.join(jre_final_path, 'local_policy.jar')
  final_export_policy = ::File.join(jre_final_path, 'US_export_policy.jar')

  windows_zipfile staging_path do
    source url
    checksum zip_checksum
    action :unzip
    not_if { ::File.exist? staging_local_policy }
    notifies :create, "file[#{final_local_policy}]"
    notifies :create, "file[#{final_export_policy}]"
  end

  file final_local_policy do
    rights :full_control, node['java']['windows']['owner']
    content lazy { ::File.read(staging_local_policy) }
    action :nothing
  end

  file final_export_policy do
    rights :full_control, node['java']['windows']['owner']
    content lazy { ::File.read(staging_export_policy) }
    action :nothing
  end

else
  package 'unzip'
  package 'curl'

  execute 'download jce' do
    command <<-EOF
      rm -rf #{Chef::Config[:file_cache_path]}/java_jce
      mkdir -p #{Chef::Config[:file_cache_path]}/java_jce
      cd #{Chef::Config[:file_cache_path]}/java_jce

      curl -L --cookie '#{jce_cookie}' -o jce.zip #{jce_url}
      # fail the resource if the checksum does not match
      # this should only happen if oracle download terms are not accepted and downloading directly from oracle
      echo "#{jce_checksum}  jce.zip" | #{checksum_bin} -c >/dev/null
    EOF
    # if jar is already in the right location then don't need to download the JCE again
    not_if { ::File.exist?(::File.join(node['java']['oracle']['jce']['home'], jdk_version, 'US_export_policy.jar')) }
  end

  execute 'extract jce' do
    command <<-EOF
      unzip -o jce.zip
      find -name '*.jar' | xargs -I JCE_JAR mv JCE_JAR #{node['java']['oracle']['jce']['home']}/#{jdk_version}/
    EOF
    cwd "#{Chef::Config[:file_cache_path]}/java_jce"
    creates ::File.join(node['java']['oracle']['jce']['home'], jdk_version, 'US_export_policy.jar')
  end

  %w(local_policy.jar US_export_policy.jar).each do |jar|
    jar_path = ::File.join(node['java']['java_home'], 'jre', 'lib', 'security', jar)
    # remove the jars already in the directory
    file jar_path do
      action :delete
      not_if { ::File.symlink? jar_path }
    end
    link jar_path do
      to ::File.join(node['java']['oracle']['jce']['home'], jdk_version, jar)
    end
  end
end
