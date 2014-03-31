#
# Cookbook Name:: reprepro
# Recipe:: default
#
# Author:: Joshua Timberman <joshua@opscode.com>
# Copyright 2010, Opscode
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

include_recipe "build-essential"
include_recipe 'gpg'

databag_id = node['reprepro']['databag_id'] || 'main'

apt_repo = unless node['reprepro']['disable_databag']
   data_bag_item('reprepro', databag_id)
else
   node['reprepro']
end

%w{
  apt-utils 
  dpkg-dev
  reprepro
  debian-keyring
  devscripts
  dput
}.each do |pkg|
  package pkg
end

[ apt_repo["repo_dir"], apt_repo["incoming"] ].each do |dir|
  directory dir do
    owner "nobody"
    group "nogroup"
    mode "0755"
    recursive true
  end
end

%w{ conf db dists pool tarballs }.each do |dir|
  directory "#{apt_repo["repo_dir"]}/#{dir}" do
    owner "nobody"
    group "nogroup"
    mode "0755"
    recursive true
  end
end

unless node[:reprepro].nil? or node[:reprepro][:fqdn].nil?
   apt_repo["fqdn"] = node[:reprepro][:fqdn]
end

%w{ distributions incoming pulls }.each do |conf|
  template "#{apt_repo["repo_dir"]}/conf/#{conf}" do
    source "#{conf}.erb"
    mode "0644"
    owner "nobody"
    group "nogroup"
    variables(
      :allow => apt_repo["allow"],
      :codenames => apt_repo["codenames"],
      :architectures => apt_repo["architectures"],
      :incoming => apt_repo["incoming"],
      :pulls => apt_repo["pulls"],
      :signwith => apt_repo["pgp"]["email"],
      :fqdn => apt_repo["fqdn"]
    )
  end
end

pgp_home = node['reprepro']['gnupg_home']
pgp_email = apt_repo['pgp']['email'] || node[:gpg][:name][:email] 
pgp_cmd = "gpg --homedir #{pgp_home} "
pgp_key = "#{apt_repo["repo_dir"]}/#{pgp_email}.gpg.key"
reprepro_cmd = "reprepro --gnupghome=#{pgp_home} -Vb #{apt_repo[:repo_dir]} "

if apt_repo['pgp']['email']

  Chef::Log.info('No apt_repo Clause')

  execute "import packaging key" do
    command "/bin/echo -e '#{apt_repo["pgp"]["private"]}' | #{pgp_cmd} --import -'"
    user "root"
    cwd "/root"
  #  ignore_failure true
    environment "GNUPGHOME" => pgp_home
    not_if "GNUPGHOME=#{pgp_home} #{pgp_cmd} --list-secret-keys --fingerprint #{pgp_email} --yes | egrep -qx '.*Key fingerprint = #{apt_repo["pgp"]["fingerprint"]}'"
  end
  
  file pgp_key do
    content apt_repo["pgp"]["public"]
    mode 0644
    owner "nobody"
    group "nogroup"
  end

else

  Chef::Log.info('No apt_repo Else Clause')

  execute "sudo -u #{node['gpg']['user']} -i #{pgp_cmd} --armor --export #{node['gpg']['name']['real']} > #{pgp_key}" do
    creates pgp_key
  end

  file pgp_key do
    mode 0644
    owner "nobody"
    group "nogroup"
  end

end

execute "#{reprepro_cmd} export" do
  action :nothing
  subscribes :run, resources(:file => pgp_key), :immediately
  environment "GNUPGHOME" => pgp_home
end

execute "#{reprepro_cmd} createsymlinks" do
  action :nothing
  subscribes :run, resources(:template => apt_rep['repo_dir']+'/conf/distributions' ), :immediately
  environment "GNUPGHOME" => pgp_home
end

if apt_repo[:enable_repository_on_host]
  include_recipe 'apt'

  execute "apt-key add #{pgp_key}" do
    action :nothing
     subscribes :run, "file[#{pgp_key}]", :immediately
  end

  apt_repository "reprepro" do
    uri "file://#{apt_repo[:repo_dir]}"
    distribution node['lsb']['codename']
    components ["main"]
  end
end

begin
  include_recipe "reprepro::#{node['reprepro']['server']}"
rescue Chef::Exceptions::RecipeNotFound
  Chef::Log.warn "Missing recipe for #{node['reprepro']['server']}, only 'nginx'or 'apache2' are available"
end
