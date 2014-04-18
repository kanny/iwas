require 'aws-sdk-core'
require 'json'
require 'pp'
require 'uri'

USER_DIR_PATH = "./users"
GROUP_DIR_PATH = "./groups"
ROLE_DIR_PATH = "./roles"

Aws.config = {
  access_key_id: ENV['AWS_ACCESS_KEY_ID'],
  secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
  region: 'us-east-1'
}

Dir.mkdir(USER_DIR_PATH) unless Dir.exist?(USER_DIR_PATH)
Dir.mkdir(GROUP_DIR_PATH) unless Dir.exist?(GROUP_DIR_PATH)
Dir.mkdir(ROLE_DIR_PATH) unless Dir.exist?(ROLE_DIR_PATH)

iam = Aws::IAM.new
iam = Aws.iam
iam.list_users['users'].each do |user|
  user_dir = "#{USER_DIR_PATH}/#{user.user_name}"
  Dir.mkdir(user_dir) if !Dir.exist?(user_dir)
  policies = iam.list_user_policies(user_name: user.user_name)
  policies['policy_names'].each do |policy|
    file_path = "#{user_dir}/#{policy}.json"
    resp = iam.get_user_policy(user_name: user.user_name, policy_name: policy)
    File.write(file_path, URI.unescape(resp.policy_document))
    puts "wrote #{file_path}"
  end
end

iam.list_groups['groups'].each do |group|
  group_dir = "#{GROUP_DIR_PATH}/#{group.group_name}"
  Dir.mkdir(group_dir) if !Dir.exist?(group_dir)
  policies = iam.list_group_policies(group_name: group.group_name)
  policies['policy_names'].each do |policy|
    file_path = "#{group_dir}/#{policy}.json"
    resp = iam.get_group_policy(group_name: group.group_name, policy_name: policy)
    File.write(file_path, URI.unescape(resp.policy_document))
    puts "wrote #{file_path}"
  end
end

iam.list_roles['roles'].each do |role|
  role_dir = "#{ROLE_DIR_PATH}/#{role.role_name}"
  Dir.mkdir(role_dir) if !Dir.exist?(role_dir)
  policies = iam.list_role_policies(role_name: role.role_name)
  policies['policy_names'].each do |policy|
    file_path = "#{role_dir}/#{policy}.json"
    resp = iam.get_role_policy(role_name: role.role_name, policy_name: policy)
    File.write(file_path, URI.unescape(resp.policy_document))
    puts "wrote #{file_path}"
  end
end
