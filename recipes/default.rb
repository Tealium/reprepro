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

#node.set[:apache][:listen_ports] = node[:apache][:listen_ports] | Array(node[:reprepro][:listen_port])

include_recipe "aws_ebs_disk"
include_recipe "build-essential"
include_recipe "apache2"


execute "apt-get-update" do
  command "apt-get update --quiet -y"
  ignore_failure true
end
    app_environment = node["app_environment"] || "development"
    Chef::Log.info("app_environment is: #{app_environment}")
    apt_repo = data_bag_item("reprepro", app_environment)
    Chef::Log.info("apt_repo is: #{apt_repo["repo_dir"]}")
    Chef::Log.info("apt_repo is: #{apt_repo["incoming"]}")
    Chef::Log.info("apt_repo is: #{apt_repo["description"]}")
    Chef::Log.info("apt_repo is: #{apt_repo["codenames"]}")
    Chef::Log.info("apt_repo is: #{apt_repo["allow"]}")
    Chef::Log.info("apt_repo is: #{apt_repo["pulls"]}")

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
      "signwith" => apt_repo["pgp"]["email"],
      "fqdn" => apt_repo["fqdn"]
    )
  end
end

if(apt_repo)
  Chef::Log.info('No apt_repo Clause')
  pgp_key = "#{apt_repo["repo_dir"]}/#{apt_repo["pgp"]["email"]}.gpg.key"

  execute "import packaging key" do
    #command "/bin/echo -e '#{apt_repo["pgp"]["private"]}' > /tmp/foo.txt; yes | gpg --import --yes /tmp/foo.txt; rm /tmp/foo.txt"
    #TODO: I give up for now. Need to fix this.
    command "/bin/echo -e '#{apt_repo["pgp"]["private"]}' > /tmp/foo.txt"
    user "root"
    cwd "/root"
    ignore_failure true
    environment "GNUPGHOME" => node["reprepro"]["gnupg_home"]
    not_if "GNUPGHOME=#{node["reprepro"]["gnupg_home"]} gpg --list-secret-keys --fingerprint #{apt_repo["pgp"]["email"]} --yes | egrep -qx '.*Key fingerprint = #{apt_repo["pgp"]["fingerprint"]}'"
  end

  template pgp_key do
    source "pgp_key.erb"
    mode "0644"
    owner "nobody"
    group "nogroup"
    variables(
      :pgp_public => apt_repo["pgp"]["public"]
    )
  end
else
  Chef::Log.info('No apt_repo Else Clause')
  pgp_key = "#{apt_repo[:repo_dir]}/#{node[:gpg][:name][:email]}.gpg.key"
  node.default[:reprepro][:pgp_email] = node[:gpg][:name][:email]

  execute "sudo -u #{node[:gpg][:user]} -i gpg --armor --export #{node[:gpg][:name][:real]} > #{pgp_key}" do
    creates pgp_key
  end

  file pgp_key do
    mode 0644
    owner "nobody"
    group "nogroup"
  end

  execute "reprepro -Vb #{apt_repo[:repo_dir]} export" do
    action :nothing
    subscribes :run, resources(:file => pgp_key), :immediately
    environment "GNUPGHOME" => apt_repo[:gnupg_home]
  end
end

if(apt_repo[:enable_repository_on_host])
  include_recipe 'apt'

  execute "apt-key add #{pgp_key}" do
    action :nothing
    if(apt_repo)
      subscribes :run, resources(:template => pgp_key), :immediately
    else
      subscribes :run, resources(:file => pgp_key), :immediately
    end
  end

  apt_repository "reprepro" do
    uri "file://#{apt_repo[:repo_dir]}"
    distribution node.lsb.codename
    components ["main"]
  end
end

template "#{node[:apache][:dir]}/sites-available/apt_repo.conf" do
  source "apt_repo.conf.erb"
  mode 0644
  variables(
    :repo_dir => apt_repo["repo_dir"],
    "email" => "devopts@tealium.com",
    "fqdn" => apt_repo["fqdn"]

  )
end

apache_site "apt_repo.conf"

apache_site "000-default" do
  enable false
end
