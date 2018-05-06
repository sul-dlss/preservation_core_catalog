# This file contains the record creation calls needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).

# it should be safe to run this repeatedly, as the methods it calls only add new entries from the configs,
# and leave existing entries untouched.
# this should be run very infrequently, and lots of other data relies on what's seeded here, and PG is pretty
# efficient about locking strategy, so use the strictest transaction isolation level (serializable):
# http://api.rubyonrails.org/classes/ActiveRecord/ConnectionAdapters/DatabaseStatements.html#method-i-transaction
# https://www.postgresql.org/docs/current/static/transaction-iso.html
ApplicationRecord.transaction(isolation: :serializable) do
  PreservationPolicy.seed_from_config
  EndpointType.seed_from_config
  Endpoint.seed_storage_root_endpoints_from_config(
    Endpoint.default_storage_root_endpoint_type, [PreservationPolicy.default_policy]
  )
  Endpoint.seed_archive_endpoints_from_config(
    Endpoint.default_archive_endpoint_type, [PreservationPolicy.default_policy]
  )
end

puts "seeded database.  state of seeded object types after seeding:"
puts "> PreservationPolicy.all: #{PreservationPolicy.all.to_a}"
puts "> EndpointType.all: #{EndpointType.all.to_a}"
puts "> Endpoint.all: #{Endpoint.all.to_a}"
