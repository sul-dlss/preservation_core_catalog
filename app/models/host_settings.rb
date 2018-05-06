# Lets us consolidate shared_configs for almost identical machines
class HostSettings
  def self.archive_endpoints
    Settings.archive_endpoint_map[archive_endpoint_lookup_name] || {}
  end

  # @return [Config::Options, Hash] key/value pairs of name: file_path
  def self.storage_roots
    Settings.storage_root_map[storage_root_lookup_name] || {}
  end

  # @return [String] hostname depending on environment
  def self.archive_endpoint_lookup_name
    Rails.env.production? ? parsed_hostname : 'default'
  end

  # @return [String] hostname depending on environment
  def self.storage_root_lookup_name
    Rails.env.production? ? parsed_hostname : 'default'
  end

  # @return [String] modified hostname
  def self.parsed_hostname
    Socket.gethostname.underscore.remove('.stanford.edu')
  end
end
