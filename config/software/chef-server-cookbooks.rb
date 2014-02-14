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

name "chef-server-cookbooks"

dependency "rsync"

source :path => File.expand_path("files/chef-server-cookbooks", Omnibus.project_root)

build do
  command "mkdir -p #{install_dir}/embedded/cookbooks"
  command "#{install_dir}/embedded/bin/rsync --delete -a ./ #{install_dir}/embedded/cookbooks/"
  block do
    File.open("#{install_dir}/embedded/cookbooks/pre_upgrade_setup.json", "w") do |f|
      f.puts "{\"run_list\": [ \"recipe[#{project.name}::pre_11.1_upgrade_setup]\" ]}"
    end
  end
end
