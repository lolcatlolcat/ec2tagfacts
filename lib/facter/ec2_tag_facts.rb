# Fact: ec2_tag_facts
#
# Purpose:
#   Set AWS EC2 instance tags as facts.
#
# Source:
#   https://github.com/BIAndrews/ec2tagfacts
#
# Author:
#   Bryan Andrews (https://bryanandrews.org)

require "net/http"
require 'json' # hint: yum install ruby-json, or apt-get install ruby-json
require "uri"
require "date"
require 'open3'


def debug_msg(txt)
  if $debug.is_a? String
    File.open($debug, 'a') { |file| file.write(Time.now.strftime("%Y/%m/%d %H:%M") + " " + txt + "\n") }
  end
end

####################################################
#
# Start
#

begin

  ################################################################
  #
  # Get the AWS EC2 instance ID from http://169.254.169.254/
  #

  uri = URI.parse("http://169.254.169.254")
  http = Net::HTTP.new(uri.host, uri.port)
  http.open_timeout = 4
  http.read_timeout = 4
  request = Net::HTTP::Get.new("/latest/meta-data/instance-id")
  response = http.request(request)
  instance_id = response.body

  debug_msg("Instance ID is #{instance_id}")

rescue

  debug_msg("This is not an AWS EC2 instance or unable to contact the AWS instance-data web server.")

end


if !instance_id.is_a? String then

  # We couldn't find an instance string. Not an EC2 instance?

  debug_msg("Something bad happened since there was no error but this isn't a string.")

else

   # We have an instance ID we continue on...

  ##############################################################################################
  #
  # Get the AWS EC2 instance region from http://instance-data/ and then shorten the region
  # for example we convert us-west-2b into us-west-2 in order to get the tags.
  #

  request2 = Net::HTTP::Get.new("/latest/meta-data/placement/availability-zone")
  response2 = http.request(request2)
  r = response2.body

  region = /.*-.*-[0-9]/.match(r)

  debug_msg("Region is #{region}")

  ###########################################################
  #
  # Get the aws ec2 instance tags as a JSON string
  #

  begin

    # Some edge cases may require multiple attempts to re-run 'aws ec2 describe-tags' due to API rate limits
    # Making up to 6 attempts with sleep time ranging between 4-10 seconds after each unsuccessful attempt
    for i in 1..6
      # This is why aws cli is required
      debug_msg("aws ec2 describe-tags --filters \"Name=resource-id,Values=#{instance_id}\" --region #{region} --output json")
      jsonString, stderr_str, status = Open3.capture3("aws ec2 describe-tags --filters \"Name=resource-id,Values=#{instance_id}\" --region #{region} --output json")

      # If the instance does not have permission this will never work
      if stderr_str.include? "UnauthorizedOperation" then
        debug_msg("Instance does not have permission to access its tags")
        return
      end
      break if jsonString != ''
      sleep rand(4..10)
    end

    debug_msg("JSON is...\n#{jsonString}")

    # convert json string to hash
    hash = JSON.parse(jsonString)

    if hash.is_a? Hash then

      debug_msg("Hash of tags found")

      if hash.has_key?("Tags") then

        result = {}

        ################################################################################
        #
        # Loop through all tags
        #

        hash['Tags'].each do |child|

          # Name it and make sure its lower case and convert spaces to understores
          name = child['Key'].to_s
          name.downcase!
          name.gsub!(/\W+/, "_")
          fact = "ec2_tag_#{name}"

          val = child['Value'].to_s
          val.downcase!
          val.gsub!(/\W+/, "_")
          tagval = "#{val}"

          debug_msg("Setting fact #{fact} to #{tagval}")

          # append to the hash for structured fact later
          result[name] = result[tagval]

          debug_msg("Added #{fact} to results hash for structured fact")

          # set puppet fact - flat version
          Facter.add("#{fact}") do
            setcode do
              child[tagval]
            end
          end

        end

        ################################################################################
        #
        # Set structured fact
        #

        if defined?(result) != nil
          Facter.add(:ec2_tags) do
            setcode do
              result
            end
          end
        end

        debug_msg("Structured fact is: #{result}")

      else

        debug_msg("No tags found")

      end

    end

  rescue # Ignore if awscli had any issues

    debug_msg("awscli exec failed")

  end
end