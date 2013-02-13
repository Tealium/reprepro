name             "reprepro"
maintainer       "Opscode"
maintainer_email "cookbooks@opscode.com"
license          "Apache 2.0"
description      "Installs/Configures reprepro for an apt repository"
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          "0.2.7"

depends "build-essential"
depends "apache2"
depends "aws_ebs_disk"
recommends "gpg"
depends "apt"

recipe "reprepro", "Installs and configures reprepro for an apt repository"
