require 'aws-sdk-core'
require 'json'
require 'time'
require 'zlib'
require 'yaml'
require 'git'

Aws.config = {
  access_key_id: ENV['AWS_ACCESS_KEY_ID'],
  secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
  region: 'us-east-1'
}

config = YAML.load_file("config.yml")

USER_DIR_PATH = "./users"
GROUP_DIR_PATH = "./groups"
ROLE_DIR_PATH = "./roles"
LOG_DIR = "./logs"
QUEUE_URL = config["queue_url"]

UPDATE_ACTIONS = [
  "PutUserPolicy",
  "PutGroupPolicy",
  "PutRolePolicy",
  "CreateUser",
  "CreateGroup",
  "CreateRole",
  "DeleteGroup",
  "DeleteGroupPolicy",
  "DeleteUser",
  "DeleteUserPolicy",
  "DeleteRole",
  "DeleteRolePolicy",
]

class SQSMessage
  def initialize(bucket, key, timestamp)
    @bucket = bucket
    @key = key
    @timestamp = timestamp
  end

  attr_reader :bucket, :key, :timestamp
end

class Event
  def initialize(rows)
    @action = rows["eventName"] || nil
    @date = Time.parse(rows["eventTime"])
    @params = rows["requestParameters"] || {}
    @requser = rows["userIdentity"]["userName"]
    @reqarn = rows["userIdentity"]["arn"]
    @name = @params["policyName"] || nil
    @doc = @params["policyDocument"] || nil
    @user = @params["userName"] || nil
    @group = @params["groupName"] || nil
    @role = @params["roleName"] || nil
  end

  def update_event?
    UPDATE_ACTIONS.include?(self.action)
  end

  attr_reader :action, :requser, :reqarn, :date, :name, :doc, :user, :group, :role
end

def update_repo(event)
  g = Git.open(".")
  case event.action
  when "PutUserPolicy"
    fpath = "#{USER_DIR_PATH}/#{event.user}/#{event.name}.json"
    File.open(fpath, "w+") do |f|
      f.puts(event.doc)
    end
  when "PutGroupPolicy"
    fpath = "#{GROUP_DIR_PATH}/#{event.group}/#{event.name}.json"
    File.open(fpath, "w+") do |f|
      f.puts(event.doc)
    end
  when "PutRolePolicy"
    fpath = "#{ROLE_DIR_PATH}/#{event.role}/#{event.name}.json"
    File.open(fpath, "w+") do |f|
      f.puts(event.doc)
    end
  when "CreateUser"
    dpath = "#{USER_DIR_PATH}/#{event.user}"
    Dir.mkdir(dpath)
    fpath = "#{dpath}/placeholder"
    File.open(fpath,"w+") do |f|
      f.puts "Don't remove this file"
    end
  when "CreateGroup"
    dpath = "#{GROUP_DIR_PATH}/#{event.group}"
    Dir.mkdir(dpath)
    fpath = "#{dpath}/placeholder"
    File.open(fpath,"w+") do |f|
      f.puts "Don't remove this file"
    end
  when "CreateRole"
    dpath = "#{ROLE_DIR_PATH}/#{event.role}"
    Dir.mkdir(dpath)
    fpath = "#{dpath}/placeholder"
    File.open(fpath,"w+") do |f|
      f.puts "Don't remove this file"
    end
  when "DeleteUser"
    fpath = "#{USER_DIR_PATH}/#{event.user}"
    Dir.rm_r(fpath)
  when "DeleteGroup"
    fpath = "#{GROUP_DIR_PATH}/#{event.group}"
    Dir.rm_r(fpath)
  when "DeleteRole"
    fpath = "#{ROLE_DIR_PATH}/#{event.role}"
    Dir.rm_r(fpath)
  when "DeleteUserPolicy"
    fpath = "#{USER_DIR_PATH}/#{event.user}/#{event.name}.json"
    FileUtils.rm(fpath)
  when "DeleteGroupPolicy"
    fpath = "#{GROUP_DIR_PATH}/#{event.group}/#{event.name}.json"
    FileUtils.rm(fpath)
  when "DeleteRolePolicy"
    fpath = "#{ROLE_DIR_PATH}/#{event.role}/#{event.name}.json"
    FileUtils.rm(fpath)
  end
  g = Git.open(".")
  g.add(fpath)
  g.commit("Update IAM Policy. This change made by #{event.reqarn} at #{event.date}.")
end

messages = []
files = []

sqs = Aws::SQS.new
s3 = Aws::S3.new

Dir.mkdir(LOG_DIR) unless Dir.exist?(LOG_DIR)

loop do
  resp = sqs.receive_message(queue_url: QUEUE_URL, max_number_of_messages: 10)
  break if resp['messages'].nil?
  resp['messages'].each do |message|
    body = JSON.parse(message['body'])
    bucket_and_key = JSON.parse(body['Message'])
    messages.push(SQSMessage.new(bucket_and_key['s3Bucket'], bucket_and_key['s3ObjectKey'].first, body['Timestamp']))
  end
end
messages.sort_by! {|message| message.timestamp}
messages.each do |message|
  filename = message.key.split("/").last
  files.push(filename)
  resp = s3.get_object({bucket: message.bucket, key: message.key}, target: "#{LOG_DIR}/#{filename}")
  puts "write #{filename}"
end

files.each do |file|
  obj = JSON.parse(Zlib::GzipReader.open("#{LOG_DIR}/#{file}").read)
  obj["Records"].each do |row|
    ev = Event.new(row)
    if ev.update_event?
      update_repo(ev)
    end
  end
end

g = Git.open(".")
g.push
