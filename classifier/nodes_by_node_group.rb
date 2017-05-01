#!/opt/puppetlabs/puppet/bin/ruby

require 'json'
require 'optparse'

def debug(str)
  puts "DEBUG: #{str}" if $options[:debug] 
end

# List out node groups
def list_groups 
  ret = {}
  $groups.each do |g|
    puts g['name']
  end
  return nil
end

# Create a hash mapping group id to name
def build_id_to_name() 
  ret = {}
  $groups.each do |g|
    ret[g['name'].downcase] = g['id']
  end
  return ret
end

# Return a list of rules
def get_rules(arr, group_id,first=true)
  $groups.each do |group|
    if(group['id'] == group_id) then
      if(group['rule'].to_s != '') then
        debug "Adding rules '#{group['rule'].to_s}' for group '#{group['name']}'"
        arr << group['rule'].to_s
      elsif(first) then
        debug "Initial group has no rules, so nothing matches"
        return nil
      end
      if(group['id'] != group['parent']) then
        get_rules(arr, group['parent'], false)
      end
    end
  end
  return nil
end

def build_query_string(arr)
  if(arr.length == 0) then
    debug "No rules found for '#{$group_to_find}'"
    debug $groups
  elsif(arr.length == 1)
    query_string = "#{arr[0]}"
  elsif(arr.length == 2)
    query_string = "[\"and\",#{arr.join ","}]"
  else
    query_string = "[\"and\",#{arr.pop},#{arr.pop}]"
    while(arr.length > 0) do
      query_string = "[\"and\",#{query_string},#{arr.pop}]"
    end
  end
  
  # If the query string is empty, then we don't want to match anything.
  if(query_string.nil?) then
    query_string = '["=","certname","No Matches"]'
  end
  
  query_string.gsub! '"name"', '"certname"'
  debug "Final query string = '#{query_string}'"
  return query_string
end

# main
CONSOLE_NODE_FQDN = `hostname -f`.chomp
PUPPETDB_NODE_FQDN = "localhost"

$options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: nodes_by_node_group.rb [flags] <Group Name> or nodes_by_node_group.rb --list"
  opts.on("-d","--debug","Enable debug output") do |d|
    $options[:debug] = d
  end
  opts.on("-l","--list","List available groups") do |l|
    $options[:list] = l
  end
end.parse!

data = `curl -s --cert $(puppet config print hostcert) --key $(puppet config print hostprivkey) --cacert $(puppet config print localcacert) https://#{CONSOLE_NODE_FQDN}:4433/classifier-api/v1/groups`
retcode = $?.exitstatus
if(retcode != 0) then
  if(retcode == 7) then
    puts "ERROR: Unable to reach #{CONSOLE_NODE_FQDN}:4433"
    puts "       Is pe-console-services running?"
  else
    puts "ERROR: Failed to curl endpoint, retcode=#{retcode}"
  end
  exit retcode
end

$groups = JSON.parse(data)

if($options[:list]) then
  list_groups
  exit 0
end

$group_to_find ||= ARGV.join " "
$group_to_find.downcase
if($group_to_find.nil?) then
  puts "Usage: nodes_by_node_group.rb <Group Name> [flags]"
  exit -1
end

id_hash = build_id_to_name
get_rules(arr = [], id_hash[$group_to_find])
query_string = build_query_string(arr)

curlcmd = "curl -s -G http://#{PUPPETDB_NODE_FQDN}:8080/pdb/query/v4/nodes --data-urlencode 'query=#{query_string}'"
debug curlcmd
data = `#{curlcmd}`
retcode = $?.exitstatus
if(retcode != 0) then
  if(retcode == 7) then
    puts "ERROR: Unable to reach localhost:8080"
    puts "       Is pe-puppetdb running on this host?"
  else
    puts "ERROR: Failed to curl endpoint, retcode=#{retcode}"
  end
  exit retcode
end

nodes = JSON.parse(`#{curlcmd}`)

title = "Nodes for the class '#{$group_to_find}'"
puts title
puts "=" * title.length
if(nodes.count != 0) then
  nodes.each do |node|
    puts node['certname']
  end
end
puts "Total nodes: #{nodes.count}"
